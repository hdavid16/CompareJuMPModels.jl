module CompareJuMPModels
    using JuMP

    export get_variable_names, compare_variable_names, compare_variable_bounds
    export compare_constraint_types, compare_constraint_refs, compare_objective_functions
    export run_model_comparisons

    function get_variable_names(m1, m2)
        #extract variables from the models
        vars1 = all_variables(m1)
        vars2 = all_variables(m2)
        #extract variable names
        varnames1 = Set(name.(vars1))
        varnames2 = Set(name.(vars2))
        return varnames1, varnames2
    end

    function compare_variable_names(m1, m2; verbose=false)
        println("Comparing variable string names...")
        varnames1, varnames2 = get_variable_names(m1, m2)
        #compare names
        miss1, miss2 = [], []
        if varnames1 == varnames2
            println("All $(length(varnames1)) variable names are the same.")
        else
            miss1 = setdiff(varnames2, varnames1)
            miss2 = setdiff(varnames1, varnames2)
            if verbose
                println(length(miss1)," variables missing from model 1:\n\t", join(miss1,"\n\t"))
                println(length(miss2)," variables missing from model 2:\n\t", join(miss2,"\n\t"))
            else
                println(length(miss1)," variables missing from model 1.")
                println(length(miss2)," variables missing from model 2.")
            end
        end
        return miss1, miss2
    end

    function compare_variable_bounds(m1, m2; verbose=false)
        println("Comparing variable bounds...")
        varnames1, varnames2 = get_variable_names(m1, m2)
        varnames = intersect(varnames1, varnames2)
        lbdiff, ubdiff = [], []
        for vname in varnames
            v1 = variable_by_name(m1, vname)
            v2 = variable_by_name(m2, vname)
            if has_lower_bound(v1) && has_lower_bound(v2) && (lower_bound(v1) != lower_bound(v2))
                push!(lbdiff, vname)
            elseif !has_lower_bound(v1) ⊻ !has_lower_bound(v2)
                push!(lbdiff, vname)
            end
            if has_upper_bound(v1) && has_upper_bound(v2) && (upper_bound(v1) != upper_bound(v2))
                push!(ubdiff, vname)
            elseif !has_upper_bound(v1) ⊻ !has_upper_bound(v2)
                push!(ubdiff, vname)
            end
        end

        if isempty(varnames)
            println("There are no common variables between the two models.")
        elseif isempty(lbdiff)
            println("All lower bounds are the same for the $(length(varnames)) common variables.")
        elseif verbose
            println(length(lbdiff)," lower bounds differ for the following variables:\n\t", lbdiff)
        else
            println(length(lbdiff)," lower bounds differ.")
        end
        if isempty(varnames)
            nothing
        elseif isempty(ubdiff)
            println("All upper bounds are the same for the $(length(varnames)) common variables.")
        elseif verbose
            println(length(ubdiff)," upper bounds differ for the following variables:\n\t", ubdiff)
        else
            println(length(ubdiff)," upper bounds differ.")
        end
        return lbdiff, ubdiff
    end

    function compare_constraint_types(m1, m2; verbose=false)
        println("Comparing model constraint types...")
        cons_types1 = list_of_constraint_types(m1)
        cons_types2 = list_of_constraint_types(m2)

        if verbose
            cmiss1 = setdiff(cons_types2, cons_types1)
            cmiss2 = setdiff(cons_types1, cons_types2)
            if !isempty(cmiss1)
                println("Constraint types missing from model 1:\n\t", cmiss1)
            end
            if !isempty(cmiss2)
                println("Constraint types missing from model 2:\n\t", cmiss2)
            end
        end
        for ctype in intersect(cons_types1, cons_types2)
            num_cons1 = num_constraints(m1, ctype...)
            num_cons2 = num_constraints(m2, ctype...)
            if num_cons1 != num_cons2
                println("Number of constraints of type $(split(string(ctype[2]),".")[2]) differ: $num_cons1 vs $num_cons2.")
            else
                println("Both models have the same number of constraints of type $(split(string(ctype[2]),".")[2]): $num_cons1.")
            end
        end
        for ctype in setdiff(cons_types1, cons_types2)
            num_cons1 = num_constraints(m1, ctype...)
            println("Number of constraints of type $(split(string(ctype[2]),".")[2]) differ: $num_cons1 vs 0.")
        end
        for ctype in setdiff(cons_types2, cons_types1)
            num_cons2 = num_constraints(m2, ctype...)
            println("Number of constraints of type $(split(string(ctype[2]),".")[2]) differ: 0 vs $num_cons2.")
        end
        return cons_types1, cons_types2
    end

    function compare_constraint_refs(m1, m2; verbose=false)
        println("Comparing individual constraints...")
        cons1 = all_constraints(m1, include_variable_in_set_constraints=true)
        cons2 = all_constraints(m2, include_variable_in_set_constraints=true)
        #map constraint objects to constraint indices
        cobjs_map1 = Dict(
            constraint_to_dict(con) => con.index
            for con in cons1
        )
        cobjs_map2 = Dict(
            constraint_to_dict(con) => con.index
            for con in cons2
        )
        #get differences between constraint objects
        cobjs1 = keys(cobjs_map1)
        cobjs2 = keys(cobjs_map2)
        cobj_diff1 = setdiff(cobjs2, cobjs1)
        cobj_diff2 = setdiff(cobjs1, cobjs2)
        #get constraint indices
        cidx_miss1 = [cobjs_map2[k] for k in cobj_diff1]
        cidx_miss2 = [cobjs_map1[k] for k in cobj_diff2]
        cref_miss1 = constraint_ref_with_index.(m2,cidx_miss1)
        cref_miss2 = constraint_ref_with_index.(m1,cidx_miss2)

        #compare constraints
        if isempty(cobj_diff1) && isempty(cobj_diff2)
            println("All constraints are the same.")
        elseif verbose
            println(
                length(cobj_diff1), " constraints missing from model 1:\n\t",
                join(cref_miss1,"\n\t")
            )
            println(
                length(cobj_diff2), " constraints missing from model 2:\n\t",
                join(cref_miss2,"\n\t")
            )
        else
            println(
                length(cobj_diff1), " constraints missing from model 1."
            )
            println(
                length(cobj_diff2), " constraints missing from model 2."
            )
        end
        return cref_miss1, cref_miss2
    end

    function constraint_to_dict(con::ConstraintRef{Model, MOI.ConstraintIndex{MOI.ScalarAffineFunction{U}, T}, S}) where {U,T,S}
        cobj = constraint_object(con)
        cdict = Dict{String,Any}()
        for (v, coeff) in cobj.func.terms
            cdict[name(v)] = round(coeff, digits=6)
        end
        cdict["CONSTRAINT_constant"] = cobj.func.constant
        cdict["MOI_set"] = cobj.set
        return cdict
    end

    function constraint_to_dict(con::ConstraintRef{Model, MOI.ConstraintIndex{MOI.VariableIndex, T}, S}) where {T,S}
        cobj = constraint_object(con)
        cdict = Dict{String,Any}()
        cdict[name(cobj.func)] = 1
        cdict["MOI_set"] = cobj.set
        return cdict
    end

    function constraint_to_dict(con)
        error("Constraint type $(type(con)) not supported yet. Comparisons are currently only performed on linear models.")
    end

    function compare_objective_functions(m1, m2)
        println("Comparing objective functions...")
        obj1 = objective_function(m1)
        obj2 = objective_function(m2)    
        obj1_dict = objective_to_dict(obj1)
        obj2_dict = objective_to_dict(obj2)
        if obj1_dict == obj2_dict
            println("Objective functions are the same.")
        else
            println("Objective functions are different.")
        end
        return obj1, obj2
    end

    function objective_to_dict(obj::AffExpr)
        odict = Dict{String,Any}()
        for (v, coeff) in obj.terms
            odict[name(v)] = round(coeff, digits=6)
        end
        odict["CONSTRAINT_constant"] = obj.constant
        return odict
    end

    function objective_to_dict(obj)
        error("Objective type $(type(obj)) not supported yet. Comparisons are currently only performed on linear models.")
    end

    mutable struct ModelDiffs
        variables_missing_1
        variables_missing_2
        variable_lb_diff
        variable_ub_diff
        constraints_missing_1
        constraints_missing_2
        ModelDiffs() = new(
            Set(),
            Set(),
            [],
            [],
            [],
            []
        )
    end

    function run_model_comparisons(m1, m2;
        variable_names=true,
        variable_bounds=true,
        constraint_types=true,
        constraint_refs=true,
        objective_functions=true,
        verbose=true
    )
        diff = ModelDiffs()
        if variable_names
            vmiss1, vmiss2 = compare_variable_names(m1, m2; verbose=false)
            diff.variables_missing_1 = vmiss1
            diff.variables_missing_2 = vmiss2
            println()
        end
        if variable_bounds
            lb_diff, ub_diff = compare_variable_bounds(m1, m2; verbose=false)
            diff.variable_lb_diff = lb_diff
            diff.variable_ub_diff = ub_diff
            println()
        end
        if constraint_types
            compare_constraint_types(m1, m2; verbose=false)
            println()
        end
        if constraint_refs
            cref_diff1, cref_diff2 = compare_constraint_refs(m1, m2; verbose=false)
            diff.constraints_missing_1 = cref_diff1
            diff.constraints_missing_2 = cref_diff2
            println()
        end
        if objective_functions
            compare_objective_functions(m1, m2)
            println()
        end
        return diff
    end
end
