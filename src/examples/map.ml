
let rec map f xs =
  match xs with
  | [] -> []
  | x :: xs1 -> f x :: map f xs1

let id y = y

let map_id ys
(*@ Norm(emp, ys) @*)
= map id ys

let succ x = x + 1

let map_not_id_false ys
(*@ Norm(emp, ys) @*)
= map succ ys

(* ghost function that specifies what mapping succ should return *)
let rec succ_list xs =
  match xs with
  | [] -> []
  | x :: xs1 -> succ x :: succ_list xs1

(* we use succ_list in the statement of this lemma *)
let map_succ ys
(*@ ex r; succ_list(ys, r); Norm(emp, r) @*)
= map succ ys

let rec length xs =
  match xs with
  | [] -> 0
  | x :: xs1 -> 1 + length xs1

let cl_map xs x
(*@ ex i; req x->i; ex r; length(xs, r); ex r1; Norm(r1=xs/\x->i+r, r1) @*)
= let f a = x := !x+1; a in
  map f xs

(*

Proof sketch for inductive case:

map(f, xs, r) |-  req x -> init; length(xs, r); Norm(x-> init+r /\ ret =xs, ret) 

[unfold map]

Norm (xs=hd::tl, _); f(hd, r);                         map(f, tl, r1); Norm (emp, r::r1) |-  req x -> init; length(xs, r); Norm(x-> init+r /\ ret =xs, ret) 

[unfold f]

Norm (xs=hd::tl, _); req x->init; Norm(x->init+1, hd); map(f, tl, r1); Norm (emp, hd::r1) |-  req x -> init; length(xs, r); Norm(x-> init+r /\ ret =xs, ret) 

LHS: 

Norm (xs=hd::tl, _); req x->init; 
Norm(x->init+1, hd);  req x -> init'; <=> init+1=init'
length(tl, r'); Norm(x-> init'+r' /\ ret =tl, ret) 
Norm (emp, hd::tl)  

[norm]

Norm (xs=hd::tl, _); req x->init; 
length(tl, r'); Norm(x-> init+1+r' /\ ret =hd::tl, ret) |- 

RHS:
req x -> init; length(xs, r); Norm(x-> init+r /\ ret =xs, ret) 

[unfold length]

req x -> init; Norm (xs=hd::tl, _); 
length(tl, r'); Norm(x-> init+1+r' /\ ret =xs, ret) 

*)
