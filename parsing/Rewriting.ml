
open List
open Parsetree
open Pretty
open Z3


let rec term_to_expr ctx : Parsetree.term -> Expr.expr = function
  | Num n        -> Arithmetic.Integer.mk_numeral_i ctx n
  | Var v          -> Arithmetic.Integer.mk_const_s ctx v
  | Plus (t1, t2)  -> Arithmetic.mk_add ctx [ term_to_expr ctx t1; term_to_expr ctx t2 ]
  | Minus (t1, t2) -> Arithmetic.mk_sub ctx [ term_to_expr ctx t1; term_to_expr ctx t2 ]
  | TList _
  | TListAppend (_, _) -> raise (Foo "Rewriting.ml->term_to_expr")

let rec pi_to_expr ctx : Parsetree.pi -> Expr.expr = function
  | True                -> Boolean.mk_true ctx
  | False               -> Boolean.mk_false ctx
  | Atomic (op, t1, t2) -> (
      let t1 = term_to_expr ctx t1 in
      let t2 = term_to_expr ctx t2 in
      match op with
      | EQ -> Boolean.mk_eq ctx t1 t2
      | LT -> Arithmetic.mk_lt ctx t1 t2
      | LTEQ -> Arithmetic.mk_le ctx t1 t2
      | GT -> Arithmetic.mk_gt ctx t1 t2
      | GTEQ -> Arithmetic.mk_ge ctx t1 t2)
  | And (pi1, pi2)      -> Boolean.mk_and ctx [ pi_to_expr ctx pi1; pi_to_expr ctx pi2 ]
  | Or (pi1, pi2)       -> Boolean.mk_or ctx [ pi_to_expr ctx pi1; pi_to_expr ctx pi2 ]
  | Imply (pi1, pi2)    -> Boolean.mk_implies ctx (pi_to_expr ctx pi1) (pi_to_expr ctx pi2)
  | Not pi              -> Boolean.mk_not ctx (pi_to_expr ctx pi)
  | Predicate _ -> raise (Foo "Rewriting.ml->pi_to_expr")


let check p1 p2 : bool =
  let pi =   (Not (Or (Not p1, p2))) in
  let cfg = [ ("model", "false"); ("proof", "false") ] in
  let ctx = mk_context cfg in
  let expr = pi_to_expr ctx pi in
  (* print_endline (Expr.to_string expr); *)

  let solver = Solver.mk_simple_solver ctx in
  Solver.add solver [ expr ];
  let sat = not (Solver.check solver [] == Solver.SATISFIABLE) in
  (*print_endline (Solver.to_string solver); *)
  sat

let check_pure p1 p2 : (bool * string) = 
  let sat = check  p1 p2 in
  let _ = string_of_pi p1 ^" => " ^ string_of_pi p2 in 
  let buffur = ("[PURE]"(*^(pure)*)^ " " ^(if sat then "Succeed\n" else "Fail\n")  )
  in (sat, buffur)





let rec  nullable (es:es) : bool=
  match es with
    Emp -> true
  | Bot -> false 
  | Singleton _ -> false 
  | Cons (es1 , es2) -> ( nullable es1) && ( nullable es2)
  | ESOr (es1 , es2) -> ( nullable es1) || ( nullable es2)
  | Kleene _ -> true
  | Underline -> false 
  | Stop -> raise (Foo "nullable stop") 

let nullableEff (eff:spec) : bool = 
  List.fold_left (fun acc (_, a) -> acc || (nullable a)) false eff;;

let rec fst (es:es): event list = 
  match es with
  | Bot -> []
  | Emp -> []
  | Singleton (Event ev) ->    [One ev]
  | Singleton (NotEvent ins) ->[Zero ins]
  | Singleton (HeapOp kappa) ->[EvHeapOp kappa]
  | Singleton (DelayAssert p)->[EvAssert p]
  | Cons (es1 , es2) ->  if  nullable es1 then append ( fst es1) ( fst es2) else  fst es1
  | ESOr (es1, es2) -> append ( fst es1) ( fst es2)
  | Kleene es1 ->  fst es1
  | Underline -> [Any]
  | Stop -> [StopEv]
;;

let fstEff (eff:spec) : event list = 
  List.flatten (List.map (fun (_, es) -> fst es) eff);;



let isBot (es:es) :bool= 
  match normalES es with
    Bot -> true
  | _ -> false 
  ;;

let isBotEff (eff:spec) :bool= 
  match eff with 
  | [] -> true 
  | _ -> false 
  ;;




let rec checkexist lst super: bool = 
  match lst with
  | [] -> true
  | x::rest  -> if List.mem x super then checkexist rest super
  else false 
  ;;

let rec splitCons (es:es) : es list = 

  match es with 
    ESOr (es1, es2) -> append (splitCons es1) (splitCons es2)
  | _ -> [es]

  ;;

let rec reoccur esL esR (del:evn) = 
  match del with 
  | [] -> false 
  | (es1, es2) :: rest -> 
    let tempHL = splitCons es1 in 
    let tempL = splitCons esL in 

    let subsetL = checkexist tempL tempHL in 
      (*List.fold_left (fun acc a -> acc && List.mem a tempHL  ) true tempL in*)
    
    let tempHR = splitCons es2 in 
    let tempR = splitCons esR in 

    let supersetR = checkexist tempHR tempR in 
      (*List.fold_left (fun acc a -> acc && List.mem a tempR  ) true tempHR in*)
    
    if (subsetL && supersetR) then true
    else reoccur esL esR rest (*REOCCUR*) 
  ;;
(*


let rec checkreoccur  esL rhs  (del:evn) = 
  match rhs with 
  | [] -> false 
  | (_, x, _):: xs  -> if reoccur esL x del then true else checkreoccur esL xs del 
  ;;

let rec reoccurEff lhs rhs (del:evn) = 
  match lhs with 
  | [] -> true  
  | (_, x, _) :: xs -> if checkreoccur x rhs del == false then false else (reoccurEff xs rhs del )
;;
*)

let comparePointsTo (s1, t1) (s2, t2) : bool = 
  let rec helper t1 t2 : bool = 
    match (t1, t2) with 
    | ([], []) -> true 
    | (x::xs, y::ys)  -> x == y && helper xs ys
    | _ -> false 
  in 
  (String.compare s1 s2 == 0) && helper t1 t2


let compareKappa (k1:kappa) (k2:kappa) : bool = 
  match (k1, k2) with 
  | (EmptyHeap, EmptyHeap) -> true 
  | (PointsTo pt1, PointsTo pt2) -> (*comparePointsTo*) pt1 == pt2
  | (Disjoin _, Disjoin _)
  | (Implication _, Implication _) -> raise (Foo "compareKappa TBD")
  | _ -> false


let comparePure (p1:pi) (p2:pi) : bool = 
  match (p1, p2) with 
  | (True, True)
  | (False, False) -> true 
  | (Atomic (op1, t1, t2), Atomic (op2, t3, t4)) -> 
     op1 == op2 && t1 == t3 && t2 == t4 
  | (And _, And _) 
  | (Or _, Or _) 
  | (Imply _, Imply _) 
  | (Not _, Not _) -> raise (Foo "comparePure TBD")
  | _ -> false


  


let entailsEvent (ev1:event) (ev2:event): bool =
  match (ev1, ev2) with
  | (StopEv, StopEv) -> true 
  | (_, Any) -> true 
  | (Zero (str1), Zero (str2))-> compareInstant str1 str2
  | (One (str1), One (str2)) -> compareInstant str1 str2
  | (One (str1), Zero (str2)) -> not (compareInstant str1 str2)
  | (EvHeapOp (k1), EvHeapOp (k2))-> compareKappa k1 k2
  | (EvAssert (p1), EvAssert (p2))-> comparePure p1 p2
  | (_, Zero (_)) -> true 
  | _ -> false 

  ;;

let singleton_to_event (singleton:singleton) : event = 
  match singleton with 
  | Event ins -> One ins
  | NotEvent ins -> Zero ins
  | HeapOp kappa -> EvHeapOp kappa
  | DelayAssert pi -> EvAssert pi



let rec derivative (es:es) (ev:event): es =
  match es with
  | Emp -> Bot
  | Bot -> Bot
  | Singleton singleton -> 
    if entailsEvent ev (singleton_to_event singleton) then Emp else Bot  
  | ESOr (es1 , es2) -> ESOr (derivative es1 ev, derivative es2 ev)
  | Cons (es1 , es2) -> 
      if nullable es1 
      then let efF = derivative es1 ev in 
          let effL = Cons (efF, es2) in 
          let effR = derivative es2 ev in 
          ESOr (effL, effR)
      else let efF = derivative es1 ev in 
          Cons (efF, es2)    
  | Kleene es1 -> Cons  (derivative es1 ev, es)
  | Underline -> Emp
  | Stop ->   if entailsEvent ev (StopEv) then Emp else Bot



;;

let derivativeEff (eff:spec) ev: spec = 
   (List.map (fun (pi, es) -> (pi, derivative es ev)) eff)
   ;;



let rec containment (evn: evn) (lhs:es) (rhs:es) : (bool * binary_tree) = 
  let lhs = normalES lhs in 
  let rhs = normalES rhs in 
  let entail = string_of_es lhs ^" |- " ^string_of_es rhs in 
  (* print_string (entail^"\n");  *)

  match (lhs, rhs) with
  | (ESOr (l1, l2), _ ) ->
    (* print_string (string_of_es l1 ^ "   " ^ string_of_es l2^"\n"); *)
    let (re1, tree1) = containment evn l1 rhs in 
    if not re1 then (re1, tree1)
    else 
      let (re2, tree2) = containment evn l2 rhs in 
      (re1 && re2, Node (entail, [tree1;tree2] ))
    
  | (_, ESOr (r1, r2)) -> 
    let (re1, tree1) = containment evn lhs r1 in 
    if re1 then (re1, tree1)
    else 
      let (re2, tree2) = containment evn lhs r2 in 
      (re1 || re2, Node (entail, [tree1;tree2] ))
  
  | (_, _) -> 

  if nullable lhs == true && nullable rhs==false then (false, Node (entail^ "   [DISPROVE]", []))
  else if isBot lhs then (true, Node (entail^ "   [Bot-LHS]", []))
  else if isBot rhs then (false, Node (entail^ "   [Bot-RHS]", []))
  else if reoccur lhs rhs evn then (true, Node (entail^ "   [Reoccur]", []))
  else 
    let (fst:event list) = fst lhs in 
    let newEvn = append [(lhs, rhs)] evn in 
    let rec helper (acc:binary_tree list) (fst_list:event list): (bool * binary_tree list) = 
      (match fst_list with 
        [] -> (true , acc) 
      | a::xs -> 
        let (result, (tree:binary_tree)) =  containment newEvn (derivative lhs a ) (derivative rhs a ) in 
        if result == false then (false, (tree:: acc))
        else helper (tree:: acc) xs 
      )
    in 
    let (result, trees) =  helper [] fst in 
    (result, Node (entail^ "   [UNFOLD]", trees))  
    
  ;;






let rec check_containment (lhs:spec) (rhs:spec) :(bool * binary_tree) = 
  let lhs = normalSpec lhs in 
  let rhs = normalSpec rhs in 
  let entail = string_of_inclusion lhs rhs in 
  match (lhs, rhs) with 
  | (x::x1::xs, _) -> 
    let (res1, tree1) = check_containment [x] rhs in 
    let (res2, tree2) = check_containment (x1::xs)  rhs in 
    (res1 && res2, Node (entail^ "   [LHS-DISJ]", [tree1; tree2]))
  | (_, y::y1::ys) -> 
    let (res1, tree1) = check_containment lhs [y] in 
    let (res2, tree2) = check_containment lhs (y1::ys) in 
    (res1 || res2, Node (entail^ "   [RHS-DISJ]", [tree1; tree2]))
  | ([(pi1, es1)], [(pi2, es2)]) -> 
    let (re1, str) = check_pure pi1 pi2 in 
    if re1 then containment [] es1 es2 
    else (false, Node (entail^ str, []))
    
  | ([], _) -> (true, Node ("lhs empty", []))
  | (_, []) -> (false, Node ("rhs empty", []))

;;



let printReport (lhs:spec) (rhs:spec) :(bool * float * string) = 
  let startTimeStamp = Sys.time() in
  let (re, tree) = check_containment lhs rhs in 
  let computtaion_time = ((Sys.time() -. startTimeStamp) *. 1000.0) in 
  let verification_time = "[TRS Time: " ^ string_of_float (computtaion_time) ^ " ms]" in
  let result = printTree ~line_prefix:"* " ~get_name ~get_children tree in

  let whole = "[TRS Result: " ^ (if re  then "Succeed" else "Fail" ) in 
  (re, computtaion_time, "~~~~~~~~~~~~~~~~~~~~~\n" ^
  verification_time  ^"\n"^
  whole  ^"\n"^
  "- - - - - - - - - - - - - -"^"\n" ^
  result)
  ;;


let n_GT_0 : pi =
  Atomic (LT, Var "n", Num 0)

let n_GT_1 : pi =
  Atomic (LT, Var "n", Num 5)







