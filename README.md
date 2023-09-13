# CompareJuMPModels.jl

## Example Usage
```julia
model1 = "Small_A.mps"
model2 = "Small_B.mps"

using Pkg
Pkg.add("JuMP")
using JuMP
using .CompareModels

m1 = read_from_file(model1)
m2 = read_from_file(model2)
diffs = run_model_comparisons(m1, m2)
```
