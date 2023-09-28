# CompareJuMPModels.jl

This package below will compare two JuMP models, which can either be 
created directly in JuMP or loaded from a model file (e.g., MPS). 
The following comparisons are made:
    1. Variable names
    2. Variable bounds
    3. Constraint types
    4. Constraint names
    5. Constraint coefficients
    6. Constraint sets
    7. Objective function

The major assumption is that the variables have the same names in both models.
Otherwise, the variables are assumed to be different.

Author: Hector D. Perez (2023) - Operations Research Team

## Example Usage
```julia
model1 = "./example/Small_A.mps"
model2 = "./example/Small_B.mps"

using JuMP
using CompareJuMPModels

m1 = read_from_file(model1)
m2 = read_from_file(model2)
diffs = run_model_comparisons(m1, m2)
```
