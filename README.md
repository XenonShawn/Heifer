# Automated Verification for Multi-shot Continuations 



1. for primitive shared-memory concurrency
2. for memory manipulating nested handlers
3. connection with monadic. 
4. expressiveness between algebraic effects and reset/shift 


eval $(opam env)

cd parsing
dune exec ./hip.exe ../src/sp_tests/0_heap_zero_once_twice.ml