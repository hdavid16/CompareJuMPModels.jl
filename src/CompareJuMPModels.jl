module CompareJuMPModels
    using JuMP, DataFrames

    export compare_models

    function transfer_variables(m, vnames)
        for v in vnames
            isnothing(variable_by_name(m,v)) && @variable(m, base_name=v)
        end
    end

    function transfer_constraints(m, crefs)
        for c in crefs
            is_valid(m, c) && continue
            skip_flag = false
            cobj = constraint_object(c)
            if cobj.func isa AffExpr
                new_expr = zero(AffExpr)
                for (v1, coeff) in cobj.func.terms
                    v2 = variable_by_name(m, name(v1))
                    if isnothing(v2)
                        println("Constraint $c not transfered because variable $(name(v1)) is not in model 2.")
                        skip_flag = true
                    else
                        add_to_expression!(new_expr, coeff * v2)
                    end
                end
                add_to_expression!(new_expr, cobj.func.constant)
            elseif cobj.func isa VariableRef
                v2 = variable_by_name(m, name(cobj.func))
                if isnothing(v2)
                    println("Constraint $c not transfered because variable $(name(cobj.func)) is not in model 2.")
                    skip_flag = true
                else
                    new_expr = v2
                end
            else
                error("Constraint type $(typeof(c)) not supported yet. Only linear models are supported currently.")
            end
            !skip_flag && @constraint(m, new_expr in cobj.set)
        end
    end

    function cannonicalize_model(m)
        new_m = Model()
        var_map = Dict{VariableRef,VariableRef}(
            v => @variable(new_m, base_name=name(v))
            for v in all_variables(m)
        )
        obj = objective_function(m)
        sense = objective_sense(m)
        if obj isa AffExpr
            @objective(new_m, sense, sum(var_map[v] * obj.terms[v] for v in keys(obj.terms)) + obj.constant)
        else
            error("Objective type $(typeof(obj)) not supported yet. Only linear models are supported currently.")
        end
        for con in all_constraints(m, include_variable_in_set_constraints=true)
            c = constraint_object(con)
            if c.func isa VariableRef
                new_expr = var_map[c.func]
            elseif c.func isa AffExpr
                new_expr = @expression(new_m, sum(var_map[v] * c.func.terms[v] for v in keys(c.func.terms)) + c.func.constant)
            else
                error("Constraint type $(typeof(c)) not supported yet. Only linear models are supported currently.")
            end
            if c.set isa MOI.GreaterThan
                @constraint(new_m, -(new_expr - c.set.lower) in MOI.LessThan(0))
            elseif c.set isa MOI.LessThan
                @constraint(new_m, new_expr - c.set.upper in MOI.LessThan(0))
            elseif c.set isa MOI.EqualTo
                if c.func isa VariableRef
                    @constraint(new_m, -(new_expr - c.set.value) in MOI.LessThan(0))
                    @constraint(new_m, new_expr - c.set.value in MOI.LessThan(0))
                elseif c.func isa AffExpr
                    # @constraint(new_m, new_expr - c.set.value in MOI.EqualTo(0))
                    @constraint(new_m, -(new_expr - c.set.value) in MOI.LessThan(0))
                    @constraint(new_m, new_expr - c.set.value in MOI.LessThan(0))
                else
                    error("Constraint type $(typeof(c)) not supported yet. Only linear models are supported currently.")
                end
            elseif c.set isa MOI.Interval
                @constraint(new_m, -(new_expr - c.set.lower) in MOI.LessThan(0))
                @constraint(new_m, new_expr - c.set.upper in MOI.LessThan(0))
            elseif c.set isa MOI.ZeroOne
                set_binary(new_expr)
                # @constraint(new_m, new_expr in MOI.LessThan(1))
                # @constraint(new_m, -new_expr in MOI.LessThan(0))
            elseif c.set isa MOI.Integer
                set_integer(new_expr)
            else
                error("Constraint type $(typeof(c)) not supported yet. Only mixed binary linear models are supported currently.")
            end
        end

        return new_m
    end

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
                println("Number of constraints of type $(ctype[1]) in $(split(string(ctype[2]),".")[2]) differ: $num_cons1 vs $num_cons2.")
            else
                println("Both models have the same number of constraints of type $(ctype[1]) in $(split(string(ctype[2]),".")[2]): $num_cons1.")
            end
        end
        for ctype in setdiff(cons_types1, cons_types2)
            num_cons1 = num_constraints(m1, ctype...)
            println("Number of constraints of type $(ctype[1]) in $(split(string(ctype[2]),".")[2]) differ: $num_cons1 vs 0.")
        end
        for ctype in setdiff(cons_types2, cons_types1)
            num_cons2 = num_constraints(m2, ctype...)
            println("Number of constraints of type $(ctype[1]) in $(split(string(ctype[2]),".")[2]) differ: 0 vs $num_cons2.")
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
        cdict["CONSTRAINT_constant"] = round(cobj.func.constant, digits=6)
        cdict["MOI_set"] = constraint_set(cobj.set)
        return cdict
    end

    function constraint_to_dict(con::ConstraintRef{Model, MOI.ConstraintIndex{MOI.VariableIndex, T}, S}) where {T,S}
        cobj = constraint_object(con)
        cdict = Dict{String,Any}()
        cdict[name(cobj.func)] = 1
        cdict["MOI_set"] = constraint_set(cobj.set)
        return cdict
    end

    constraint_set(set::MOI.LessThan) = MOI.LessThan(round(set.upper,digits=6))
    constraint_set(set::MOI.ZeroOne) = MOI.ZeroOne()
    constraint_set(set) = error("Constraint set type $(typeof(set)) not supported yet.")

    function constraint_to_dict(con)
        error("Constraint type $(type(con)) not supported yet. Comparisons are currently only performed on linear models.")
    end

    function compare_objective_functions(m1, m2; rtol)
        println("Comparing objective functions...")
        obj1 = objective_function(m1)
        obj2 = objective_function(m2)    
        obj1_dict = objective_to_dict(obj1)
        obj2_dict = objective_to_dict(obj2)
        obj_diff = objective_diff(obj1_dict, obj2_dict; rtol)
        if isempty(obj_diff)
            println("Objective functions are the same.")
        else
            println("Objective functions are different. $(nrow(obj_diff)) variables differ.")
        end
        if termination_status(m1) == OPTIMAL && termination_status(m2) == OPTIMAL
            obj1_dict_vals = objective_to_dict_values(obj1)
            obj2_dict_vals = objective_to_dict_values(obj2)
            obj_vals_diff = objective_diff(obj1_dict_vals, obj2_dict_vals; rtol)
        else
            obj_vals_diff = DataFrame()
        end
        return obj1, obj2, obj_diff, obj_vals_diff
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

    function objective_to_dict_values(obj::AffExpr)
        odict = Dict{String,Any}()
        for (v, _) in obj.terms
            odict[name(v)] = round(value(v), digits=6)
        end
        odict["CONSTRAINT_constant"] = obj.constant
        return odict
    end

    function objective_to_dict_values(obj)
        error("Objective type $(type(obj)) not supported yet. Comparisons are currently only performed on linear models.")
    end

    function objective_diff(obj1_dict, obj2_dict; rtol)
        df1 = DataFrame(
            Variable = collect(keys(obj1_dict)),
            Model1 = collect(values(obj1_dict))
        )
        df2 = DataFrame(
            Variable = collect(keys(obj2_dict)),
            Model2 = collect(values(obj2_dict))
        )
        dfjoin = outerjoin(df1, df2, on=:Variable)
        return subset(dfjoin, [:Model1,:Model2] => ByRow((i,j) -> ismissing(i) || ismissing(j) || !isapprox(i,j;rtol)))
    end

    mutable struct ModelDiffs
        variables_missing_1
        variables_missing_2
        variable_lb_diff
        variable_ub_diff
        constraints_missing_1
        constraints_missing_2
        objective_diff
        objective_variable_values
        ModelDiffs() = new(
            Set(),
            Set(),
            [],
            [],
            [],
            [],
            DataFrame(),
            DataFrame()
        )
    end

    function compare_models(model1, model2;
        optimizer=missing,
        variable_names=true,
        variable_bounds=true,
        constraint_types=true,
        constraint_refs=true,
        objective_functions=true,
        verbose=false,
        rtol=1e-6
    )
        diff = ModelDiffs()
        m1 = cannonicalize_model(model1)
        m2 = cannonicalize_model(model2)
        if !ismissing(optimizer)
            set_optimizer(m1, optimizer)
            set_optimizer(m2, optimizer)
            optimize!(m1)
            optimize!(m2)
        end
        if variable_names
            vmiss1, vmiss2 = compare_variable_names(m1, m2; verbose)
            diff.variables_missing_1 = vmiss1
            diff.variables_missing_2 = vmiss2
            println()
        end
        if variable_bounds
            lb_diff, ub_diff = compare_variable_bounds(m1, m2; verbose)
            diff.variable_lb_diff = lb_diff
            diff.variable_ub_diff = ub_diff
            println()
        end
        if constraint_types
            compare_constraint_types(m1, m2; verbose)
            println()
        end
        if constraint_refs
            cref_diff1, cref_diff2 = compare_constraint_refs(m1, m2; verbose)
            diff.constraints_missing_1 = cref_diff1
            diff.constraints_missing_2 = cref_diff2
            println()
        end
        if objective_functions
            _, _, obj_diff, obj_vals = compare_objective_functions(m1, m2; rtol)
            diff.objective_diff = obj_diff
            diff.objective_variable_values = obj_vals
            println()
        end
        return diff
    end
end
