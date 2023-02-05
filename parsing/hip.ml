

exception Foo of string
open Parsetree
open Asttypes
open Rewriting
open Pretty

let rec input_lines file =
  match try [input_line file] with End_of_file -> [] with
   [] -> []
  | [line] -> (String.trim line) :: input_lines file
  | _ -> failwith "Weird input_line return value"
;;



let rec shaffleZIP li1 li2 = 
  let rec aux a li = 
    match li with 
    | []-> []
    | y :: ys -> (a, y) :: (aux a ys)
  in 
  match li1 with 
  | [] -> []
  | x ::xs -> List.append (aux x li2) (shaffleZIP xs li2) 
;;


assert ((List.length (shaffleZIP [1;2;3] [4;5;6])) = 9 );;

(*
let string_of_effect_constructor x :string =
  match x.peff_kind with
  | Peff_decl(_, _) -> ""
      
  | _ -> ""
;;
type rec_flag = Nonrecursive | Recursive
*)

let string_of_payload p =
  match p with
  | PStr str -> Pprintast.string_of_structure str
  | PSig _ -> "sig"
  | PTyp _ -> "typ"
  | PPat _ -> "pattern"


let string_of_attribute (a:attribute) : string = 
  let name = a.attr_name.txt in 
  let payload = a.attr_payload in 
  Format.sprintf "name: %s, payload: %s" name (string_of_payload payload)

let string_of_attributes (a_l:attributes): string = 
  List.fold_left (fun acc a -> acc ^ string_of_attribute a ) "" a_l;;

let string_of_arg_label a = 
  match a with 
  | Nolabel -> ""
  | Labelled str -> str (*  label:T -> ... *)
  | Optional str -> "?" ^ str (* ?label:T -> ... *)

;;

let rec string_of_core_type (p:core_type) :string =
  match p.ptyp_desc with 
  | Ptyp_any -> "_"
  | Ptyp_var str -> str
  | Ptyp_arrow (a, c1, c2) -> string_of_arg_label a ^  string_of_core_type c1 ^ " -> " ^ string_of_core_type c2 ^"\n"
  | Ptyp_constr (l, c_li) -> 
    List.fold_left (fun acc a -> acc ^ a) "" (Longident.flatten l.txt)^
    List.fold_left (fun acc a -> acc ^ string_of_core_type a) "" c_li
  | Ptyp_tuple (ctLi) -> "(" ^
    (List.fold_left (fun acc a -> acc ^ "," ^ string_of_core_type a ) "" ctLi) ^ ")"

  | Ptyp_poly (str_li, c) -> 
    "type " ^ List.fold_left (fun acc a -> acc ^ a.txt) "" str_li ^ ". " ^
    string_of_core_type c 


  | _ -> "\nlsllsls\n"
  ;;

let debug_string_of_core_type t =
  Format.asprintf "type %a@." Pprintast.core_type t

let string_of_kind k : string = 
  match k with 
  | Peff_decl (inp,outp)-> 
    List.fold_left (fun acc a -> acc ^ string_of_core_type a) "" inp 
    ^
    string_of_core_type outp
    
  | Peff_rebind _ -> "Peff_rebind"
  ;;

let string_of_p_constant con : string =
  match con with 
  | Pconst_char i -> String.make 1 i
  | Pconst_string (i, _, None) -> i
  | Pconst_string (i, _, Some delim) -> i ^ delim
  | Pconst_integer (i, None) -> i
  | _ -> "string_of_p_constant"
;;

(*

  | Pconst_integer (i, Some m) ->
  paren (first_is '-' i) (fun f (i, m) -> pp f "%s%c" i m) f (i,m)
  | Pconst_float (i, None) ->
  paren (first_is '-' i) (fun f -> pp f "%s") f i
  | Pconst_float (i, Some m) ->
  paren (first_is '-' i) (fun f (i,m) -> pp f "%s%c" i m) f (i,m)
  *)

let rec string_of_pattern (p) : string = 
  match p.ppat_desc with 
  | Ppat_any -> "_"
  (* _ *)
  | Ppat_var str -> str.txt
  (* x *)
  | Ppat_constant con -> string_of_p_constant con
  | Ppat_type l -> List.fold_left (fun acc a -> acc ^ a) "" (Longident.flatten l.txt)
  | Ppat_constraint (p1, c) -> string_of_pattern p1 ^ " : "^ string_of_core_type c
  (* (P : T) *)
  | Ppat_effect (p1, p2) -> string_of_pattern p1 ^ string_of_pattern p2 ^ "\n"

  | Ppat_construct (l, None) -> List.fold_left (fun acc a -> acc ^ a) "" (Longident.flatten l.txt)
  | Ppat_construct (l, Some _p1) ->  
    List.fold_left (fun acc a -> acc ^ a) "" (Longident.flatten l.txt)
    (* ^ string_of_pattern p1 *)
  (* #tconst *)

  
  | _ -> Format.asprintf "string_of_pattern: %a\n" Pprintast.pattern p;;

let findFormalArgFromPattern (p): string list =
  match p.ppat_desc with 
  | Ppat_construct (_, None) -> []
  | Ppat_construct (_, Some _p1) -> 
    (match _p1.ppat_desc with
    | Ppat_tuple p1 -> List.map (fun a -> string_of_pattern a) p1
    | _ -> [string_of_pattern _p1]
    )

  | _ -> []


(** Given the RHS of a let binding, returns the es it is annotated with *)
let function_spec rhs =
  let attribute = false in
  if attribute then
    (* this would be used if we encode effect specs in OCaml terms via ppx *)
    (* we could do both *)
    failwith "not implemented"
  else
    let rec traverse_to_body e =
      match e.pexp_desc with
      | Pexp_fun (_, _, _, body) -> traverse_to_body body
      | _ -> e.pexp_effectspec
    in
    traverse_to_body rhs

let collect_param_names rhs =
  let rec traverse_to_body e =
    match e.pexp_desc with
    | Pexp_fun (_, _, name, body) ->
      let name =
        match name.ppat_desc with
        | Ppat_var s -> [s.txt]
        | _ ->
          (* we don't currently recurse inside patterns to pull out variables, so something like

             let f () (Foo a) = 1

             will be treated as if it has no formal params. *)
          []
      in
      name @ traverse_to_body body
    | _ -> []
  in
  traverse_to_body rhs

let rec string_of_effectList (specs:spec list):string =
  match specs with 
  | [] -> ""
  | x :: xs -> string_of_spec x ^ " /\\ "^  string_of_effectList xs 


let string_of_effectspec spec:string =
    match spec with
    | None -> "<no spec given>"
    | Some (pr, po) -> Format.sprintf "requires %s ensures %s" (string_of_spec pr) (string_of_effectList po)


let string_of_value_binding vb : string = 
  let pattern = vb.pvb_pat in 
  let expression = vb.pvb_expr in
  let attributes = vb.pvb_attributes in 
  Format.sprintf "%s = %s\n%s\n%s\n"
    (string_of_pattern pattern)
    (Pprintast.string_of_expression expression)
    (string_of_attributes attributes)
    (string_of_effectspec (function_spec expression))

  ;;



let string_of_program x : string =
  (* Pprintast.string_of_structure [x] *)
  match x.pstr_desc with
  | Pstr_value (_, l) ->
    List.fold_left (fun acc a -> acc ^ string_of_value_binding a) "" l
     
  | Pstr_effect ed -> 
    let name = ed.peff_name.txt in 
    let kind = ed.peff_kind in 
    (name^ " : " ^ string_of_kind kind)
  | _ ->  ("empty")


let debug_string_of_expression e =
  Format.asprintf "%a" (Printast.expression 0) e

let string_of_longident l =
  l |> Longident.flatten |> String.concat "."

let merge_spec (p1, es1) (p2, es2) : spec = 
  [(And (p1, p2), Cons(es1, es2))];;


let rec getIndentName (l:Longident.t): string = 
  (match l with 
        | Lident str -> str
        | Ldot (t, str) -> getIndentName t ^ "." ^ str
        | _ -> "getIndentName: dont know " ^ string_of_longident l
        )
        ;;

module SMap = Map.Make (struct
  type t = string
  let compare = compare
end)

(* information we record after seeing a function *)
type fn_spec = {
  pre: spec;
  post: spec list;
  formals: string list;
}


(* at a given program point, this captures specs for all local bindings *)
type fn_specs = fn_spec SMap.t

(* only first-order types for arguments, for now *)
type typ = TInt | TUnit | TRef of typ | TString | TTuple of (typ list)

let rec core_type_to_typ (t:core_type) =
  match t.ptyp_desc with
  | Ptyp_constr ({txt=Lident "int"; _}, []) -> TInt
  | Ptyp_constr ({txt=Lident "unit"; _}, []) -> TUnit
  | Ptyp_constr ({txt=Lident "string"; _}, []) -> TString
  | Ptyp_constr ({txt=Lident "ref"; _}, [t]) -> TRef (core_type_to_typ t)
  | Ptyp_tuple (tLi) -> TTuple (List.map (fun a -> core_type_to_typ a) tLi)
  
  | _ -> failwith ("core_type_to_typ: " ^ string_of_core_type t)

(* effect Foo : int -> (int -> int) *)
type effect_def = {
  params: typ list; (* [TInt] *)
  res: typ list * typ (* ([TInt], TInt) *)
}

type env = {
  (* module name -> a bunch of function specs *)
  modules : fn_specs SMap.t;
  current : fn_specs;
  (* the stack stores higher-order functions which may produce effects.
     an entry like a -> Foo(1) means that the variable a in scope has been applied to
     the single argument 1. nothing is said about how many arguments are remaining,
     (though that can be figured out from effect_defs) *)
  stack : stack list;
  (* remembers types given in effect definitions *)
  side_spec : side;
  effect_defs : effect_def SMap.t;
}

type variableStack = ((string * basic_t) list) ref 

let (variableStack:variableStack) = ref []

module Env = struct
  let empty = {
    modules = SMap.empty;
    current = SMap.empty;
    stack = [];
    side_spec = [];
    effect_defs = SMap.empty
  }

  let add_fn f spec env =
    { env with current = SMap.add f spec env.current }

  let add_side_spec side_list env =
    { env with side_spec = List.append (env.side_spec) side_list }

  let reset_side_spec side_list env =
    { env with side_spec = side_list }

  let add_stack paris env = 
    { env with stack = List.append  paris (env.stack) }



  let add_effect name def env =
    { env with effect_defs = SMap.add name def env.effect_defs }

  let find_fn f env =
    SMap.find_opt f env.current
  
  let fine_side f env = 
    let rec aux e =
      match e with 
      | [] -> None
      | (s, (_pre, _post)) :: xs -> 
        if String.compare s f ==0 
        then 
          let __pre = (True, _pre, []) in 
          let __post = (True, _post, []) in 
          Some (__pre, __post) else aux xs
    in aux env.side_spec
  
  let find_effect_arg_length name env =
    match SMap.find_opt name env.effect_defs with 
    | None -> None 
    | Some def -> 
      let n1 = List.length (def.params)  in 
      let (a, _) = def.res in 
      let n2 = List.length a in 
      Some (n1 + n2)


  let add_module name menv env =
    { env with modules = SMap.add name menv.current env.modules }

  (* dump all the bindings for a given module into the current environment *)
  let open_module name env =
    let m = SMap.find name env.modules in
    let fns = SMap.bindings m |> List.to_seq in
    { env with current = SMap.add_seq fns env.current }
end

let retriveStack name env = 
  let rec aux li = 
    match li with  
    | [] -> None 
    | (str, ins):: xs -> if String.compare str name == 0 then 
      Some ins else aux xs 
    in aux (env.stack)
  ;;

let string_of_fn_specs specs =
  Format.sprintf "{%s}"
    (SMap.bindings specs
    |> List.map (fun (n, s) ->
      Format.sprintf "%s -> %s/%s/%s" n
        (string_of_spec s.pre)
        (string_of_spec (List.hd s.post))
        (s.formals |> String.concat ","))
    |> String.concat "; ")

let string_of_env env =
  Format.sprintf "%s\n%s"
    (env.current |> string_of_fn_specs)
    (env.modules
      |> SMap.bindings
      |> List.map (fun (n, s) -> Format.sprintf "%s: %s" n (string_of_fn_specs s))
      |> String.concat "\n")

let rec findValue_binding name vbs: (string list) option =
  match vbs with 
  | [] -> None 
  | vb :: xs -> 
    let pattern = vb.pvb_pat in 
    let expression = vb.pvb_expr in 

    let rec helper ex= 
      match ex.pexp_desc with 
      | Pexp_fun (_, _, p, exIn) -> (string_of_pattern p) :: (helper exIn)
      | _ -> []
    in

    let arg_formal = helper expression in 
    
  
    if String.compare (string_of_pattern pattern) name == 0 then Some arg_formal
    
    (*match function_spec expression with 
      | None -> 
      | Some (pre, post) -> Some {pre = normalSpec pre; post = normalSpec post; formals = []}
    *)
   else findValue_binding name xs ;;


  (*  
  Some (Emp, Cons (Event(One ("Foo", [])), Event(One ("Foo", []))))

  let expression = vb.pvb_expr in
  let attributes = vb.pvb_attributes in 

  string_of_expression expression ^  "\n" ^
  string_of_attributes attributes ^ "\n"
  *)
  ;;

        
let is_stdlib_fn name =
  match name with
  | "!" -> true
  | _ -> false

let rec find_arg_formal name full: string list = 
  match full with 
  | [] when is_stdlib_fn name -> []
  | [] -> raise (Foo ("findProg: function " ^ name ^ " is not found!"))
  | x::xs -> 
    match x.pstr_desc with
    | Pstr_value (_ (*rec_flag*), l (*value_binding list*)) ->
        (match findValue_binding name l with 
        | Some spec -> spec
        | None -> find_arg_formal name xs
        )
    | _ ->  find_arg_formal name xs
  ;;

;;

(*
let rec eliminatePartial (es:es) env :es = 
  match es with

  | Send (eff_name, arg_list) ->
    let eff_arg_length = List.length  arg_list in 
    let eff_formal_arg_length = Env.find_effect_arg_length eff_name env in 
    (match eff_formal_arg_length with 
    | None -> raise (Foo (eff_name ^ " is not defined"))
    | Some n -> 
      (*if String.compare eff_name "Goo" == 0 then 
      raise (Foo (string_of_int eff_arg_length ^ ":"^ string_of_int n))
      else 
      *)
      (*4 Q when it is at the end, no need to add Q *)
      if eff_arg_length < n || eff_arg_length == 0 then Emp else es 
    )


  | Cons (es1, es2) ->  Cons (eliminatePartial es1 env, eliminatePartial es2 env)
      
  | ESOr (es1, es2) -> ESOr (eliminatePartial es1 env, eliminatePartial es2 env)
      
  | Omega es1 -> Omega (eliminatePartial es1 env)
      
  | Kleene es1 -> Kleene (eliminatePartial es1 env)

  | Bot -> es
  | Emp -> es
  | Event _ -> es
  | Not _ -> es 
  | Underline -> es
  | Stop -> raise (Foo "eliminatePartial")

      



  ;;

let eliminatePartiaShall spec env : spec = 
  let (pi, es, side) = spec in 
  (pi, eliminatePartial es env, side);;





*)

let rec side_binding (formal:string list) (actual: (es * es) list) : side = 
  match (formal, actual) with 
  | (x::xs, tuple::ys) -> (x, tuple) :: (side_binding xs ys)
  | _ -> []
  ;;
  

let fnNameToString fnName: string = 
  match fnName.pexp_desc with 
    | Pexp_ident l -> getIndentName l.txt 
        
    | _ -> "fnNameToString: dont know " ^ debug_string_of_expression fnName
    ;;

let expressionToBasicT ex : basic_t option=
  match ex.pexp_desc with 
  | Pexp_constant cons ->
    (match cons with 
    | Pconst_integer (str, _) -> Some (BINT (int_of_string str))
    | _ -> None (*raise (Foo (Pprintast.string_of_expression  ex ^ " expressionToBasicT error1"))*)
    )
  | Pexp_construct _ -> Some (UNIT)
  | Pexp_ident l -> Some (VARName (getIndentName l.txt))
  | _ -> None 
  (*
  | Pexp_let _ -> raise (Foo "Pexp_i")
  | Pexp_function _ -> raise (Foo "Pexp_i")
  | Pexp_fun _ -> raise (Foo "Pexp_i")
  | Pexp_apply _ -> raise (Foo "Pexp_i")
  | Pexp_match _ -> raise (Foo "Pexp_iden")
  | Pexp_try _ -> raise (Foo "Pexp_iden")
  | Pexp_tuple _ -> raise (Foo "Pexp_iden")

  | Pexp_variant _ -> raise (Foo "Pexp_ident")
  | Pexp_record _ -> raise (Foo "Pexp_ident")
  | Pexp_field _ -> raise (Foo "Pexp_ident")
  | Pexp_setfield _ -> raise (Foo "Pexp_ident")
  | Pexp_array _ -> raise (Foo "Pexp_ident")
  | Pexp_ifthenelse _ -> raise (Foo "Pexp_ident")
  | Pexp_sequence _ -> raise (Foo "Pexp_ident")
  | Pexp_while _ -> raise (Foo "Pexp_ident")
  | Pexp_for _ -> raise (Foo "Pexp_ident")
  | Pexp_constraint _ -> raise (Foo "Pexp_ident")
  | Pexp_coerce _ -> raise (Foo "Pexp_ident")


  | Pexp_send _ -> raise (Foo "Pexp_ident2")
  | Pexp_new _ -> raise (Foo "Pexp_ident2")
  | Pexp_setinstvar _ -> raise (Foo "Pexp_ident2")
  | Pexp_override _ -> raise (Foo "Pexp_ident2")
  | Pexp_letmodule _ -> raise (Foo "Pexp_ident2")
  | Pexp_letexception _ -> raise (Foo "Pexp_ident2")
  | Pexp_assert _ -> raise (Foo "Pexp_ident2")
  | Pexp_lazy _ -> raise (Foo "Pexp_ident2")
  | Pexp_poly _ -> raise (Foo "Pexp_ident3")
  | Pexp_object _ -> raise (Foo "Pexp_ident3")
  | Pexp_newtype _ -> raise (Foo "Pexp_ident3")
  | Pexp_pack _ -> raise (Foo "Pexp_ident3")
  | Pexp_open _ -> raise (Foo "Pexp_ident3")
  | Pexp_letop _ -> raise (Foo "Pexp_ident3")
  | Pexp_extension _ -> raise (Foo "Pexp_ident3")
  | Pexp_unreachable  -> raise (Foo "Pexp_ident3")
  *)
 
 (* | _ -> raise (Foo (Pprintast.string_of_expression  ex ^ " expressionToBasicT error2"))
*)

let rec var_binding (formal:string list) (actual: expression list) : (string * basic_t) list = 
  match (formal, actual) with 
  | (x::xs, expr::ys) -> 
    (match expressionToBasicT expr with
    | Some v ->
    (x, v) :: (var_binding xs ys)
    | None -> (var_binding xs ys)
    )
  | _ -> []
  ;;

let instantiateInstance (ins:instant) (vb:(string * basic_t) list)  : instant  = 
  let rec findbinding str vb_li =
    match vb_li with 
    | [] -> VARName str 
    | (name, v) :: xs -> if String.compare name str == 0 then v else  findbinding str xs
  in
  let rec helper li =
    match li with 
    | [] -> [] 
    | x ::xs -> 
      ( match x with 
        | VARName str -> (findbinding str vb) :: (helper xs)
        | _ -> x :: (helper xs)
      )
  in 
  let (a, li) = ins in (a, helper li)
;;
  

let rec instantiateArg (post_es:es) (vb:(string * basic_t) list) : es = 
  match post_es with 
  | Singleton (Event ins) -> Singleton (Event (instantiateInstance ins vb))
  | Singleton (NotEvent ins) -> Singleton (NotEvent (instantiateInstance ins vb))
  | Cons (es1, es2) -> Cons (instantiateArg es1 vb, instantiateArg es2 vb)
  | ESOr (es1, es2) -> ESOr (instantiateArg es1 vb, instantiateArg es2 vb)
  | Kleene es1 -> Kleene (instantiateArg es1 vb)
  | _ -> post_es
  ;;

let instantiateEff (eff:spec) (vb:(string * basic_t) list) : spec = 
  List.map (fun (p, t)-> (p, instantiateArg t vb)) eff;;


let rec getNormal (p: (string option * spec) list): spec = 
  match p with  
  | [] -> raise (Foo "getNormal: there is no handlers for normal return")
  | (None, s)::_ -> s
  | _ :: xs -> getNormal xs
  ;;


let rec findPolicy str_pred (policies:policy list) : (es * es) = 
  match policies with 
  | [] -> raise (Foo (str_pred ^ "'s handler is not defined!"))
  | (Eff (str, conti, afterConti))::xs  -> 
        if String.compare str str_pred == 0 then (normalES conti, normalES afterConti)
        else findPolicy str_pred xs
  | (Exn str)::xs -> if String.compare str str_pred == 0 then (Singleton (Event (str, [])), Emp) else findPolicy str_pred xs 
  | (Normal es) :: xs  -> if String.compare "normal" str_pred == 0 then (es, Emp) else findPolicy str_pred xs 


let rec reoccor_continue (li:((string*es)list)) (ev:string) index: int option  = 
  match li with 
  | [] -> None 
  | (x, _)::xs -> if String.compare x ev  == 0 then Some index else reoccor_continue xs ev (index + 1)

let rec sublist b e l = 
  if e < b then []
  else 
  match l with
    [] -> []
  | h :: t -> 
     let tail = if e=0 then [] else sublist (b-1) (e-1) t in
     if b>0 then tail else h :: tail
;;

let rec string_of_list (li: 'a list ) (f : 'a -> 'b) : string = 
  match li with 
  | [] -> ""
  | x::xs-> f x ^ "," ^ string_of_list xs f ;;




let getEffName l = 
    let (_, temp) = l in 
    match temp.pexp_desc with 
    | Pexp_construct (a, _) -> getIndentName a.txt 
    | _ -> raise (Foo "getEffName error")
;;
let getEffNameArg l = 
    let (_, temp) = l in 
    match temp.pexp_desc with 
    | Pexp_construct (_, argL) -> 
      (match argL with 
      | None -> []
      | Some a -> 
        match expressionToBasicT a with 
        | Some v -> [v]
        | None -> [])
    | _ -> raise (Foo "getEffNameArg error")
;;

let rec findNormalReturn handler = 
  match handler with 
  | [] -> raise (Foo "could not find the normal retrun")
  | a::xs -> 
    let lhs = a.pc_lhs in 
    let rhs = a.pc_rhs in 
    (match lhs.ppat_desc with 
    | Ppat_effect (_, _) 
    | Ppat_exception _   -> findNormalReturn xs 
    | _ -> rhs)
  ;;

let concatenateEffects (eff1:spec) (eff2:spec) : spec = 
  let zip = shaffleZIP eff1 eff2 in 
  List.map (fun ((p1, es1), (p2, es2)) -> (And(p1, p2), Cons (es1, es2))) zip ;;


let rec findEffectHanding handler name = 
  match handler with 
  | [] -> None 
  | a::xs -> 
    let lhs = a.pc_lhs in 
    let rhs = a.pc_rhs in 
    (match lhs.ppat_desc with 
    | Ppat_effect (p, _) -> 
      if String.compare (string_of_pattern p) name == 0 
      then 
        let formalArg = findFormalArgFromPattern p in 
        (Some (rhs, formalArg)) 
      else findEffectHanding xs  name
    | Ppat_exception p -> if String.compare (string_of_pattern p) name == 0 then (Some (rhs, [])) else findEffectHanding xs  name 
    | _ -> findEffectHanding xs  name
    )
  ;;
     
  
;;

let concatnateEffEs eff es : spec = 
  List.map (fun (p, t) -> (p, Cons (t, es))) eff;;


let rec disjunctiveES es: es list  = 
  match normalES es with 
  | ESOr (es1, es2) -> List.append (disjunctiveES es1) (disjunctiveES es2)
  | Cons (es1, es2) -> 
    let list1 = disjunctiveES es1 in 
    let list2 = disjunctiveES es2 in 
    let zip = shaffleZIP list1 list2 in 
    List.map (fun (a, b) -> Cons (a, b)) zip 
  | Kleene es1 -> disjunctiveES es1 
  | Stop 
  | Singleton _
  | Bot 
  | Emp
  | Underline -> [es]
;;

let string_of_expression_kind (expr:Parsetree.expression_desc) : string = 
  match expr with 
  | Pexp_ident _ -> "Pexp_ident"
  | Pexp_constant _ -> "Pexp_constant"
  | Pexp_let _ -> "Pexp_let"
  | Pexp_function _ -> "Pexp_function"
  | Pexp_fun _ -> "Pexp_fun"
  | Pexp_apply _ -> "Pexp_apply"
  | Pexp_match _ -> "Pexp_match"
  | Pexp_try _ -> "Pexp_try"
  | Pexp_tuple _ -> "Pexp_tuple"
  | Pexp_construct _ -> "Pexp_construct"
  | Pexp_variant _ -> "Pexp_variant"
  | Pexp_record _ -> "Pexp_record"
  | Pexp_field _ -> "Pexp_field"
  | Pexp_setfield _ -> "Pexp_setfield"
  | Pexp_array _ -> "Pexp_array"
  | Pexp_ifthenelse _ -> "Pexp_ifthenelse"
  | Pexp_sequence _ -> "Pexp_sequence"
  | Pexp_while _ -> "Pexp_while"
  | Pexp_for _ -> "Pexp_for"
  | Pexp_constraint _ -> "Pexp_constraint"
  | Pexp_coerce _ -> "Pexp_coerce"
  | Pexp_send _ -> "Pexp_send"
  | Pexp_new _ -> "Pexp_new"
  | Pexp_setinstvar _ -> "Pexp_setinstvar"
  | Pexp_override _ -> "Pexp_override"
  | Pexp_letmodule _ -> "Pexp_letmodule"
  | Pexp_letexception _ -> "Pexp_letexception"
  | Pexp_assert _ -> "Pexp_assert"
  | Pexp_lazy _ -> "Pexp_lazy"
  | Pexp_poly _ -> "Pexp_poly"
  | Pexp_object _ -> "Pexp_object"
  | Pexp_newtype _ -> "Pexp_newtype"
  | Pexp_pack _ -> "Pexp_pack"
  | Pexp_open _ -> "Pexp_open"
  | Pexp_letop _ -> "Pexp_letop"
  | Pexp_extension _ -> "Pexp_extension"
  | Pexp_unreachable -> "Pexp_unreachable"

let rec getLastEleFromList li = 
  match li with 
  | [] -> raise (Foo "getLastEleFromList impossible")
  | [x] -> x 
  | _ :: xs -> getLastEleFromList xs 

let deleteTailSYH  (li:'a list) = 
  let rec aux liIn acc =
    match liIn with 
    | [] -> raise (Foo "deleteTailSYH impossible")
    | [_] -> acc 
    | x :: xs -> aux xs (List.append acc [x])
  in aux li []


let rec expressionToTerm (exprIn: Parsetree.expression_desc) : term = 
  match exprIn with 
    | Pexp_constant (Pconst_integer (str, _)) -> (Num (int_of_string str))
    | Pexp_ident id -> Var (getIndentName (id.txt))

    | Pexp_apply (_, exprInLi) -> 
      let (_, temp) =  (List.hd exprInLi) in
      (match temp.pexp_desc with 
      | Pexp_ident id -> Var (getIndentName (id.txt))
      | _ -> raise (Foo "ai you ... 1")
      )
    | Pexp_construct (_, Some expr) -> 
      print_string ( Pprintast.string_of_expression  expr^ "\n" );
      expressionToTerm expr.pexp_desc

    | Pexp_tuple (exprLi) -> 
      if List.length exprLi == 0 then TTupple []
      else 
      (match (getLastEleFromList exprLi).pexp_desc with 
      | Pexp_construct (_, None) -> (* it is a list*)
        TList (List.map (fun a -> expressionToTerm a.pexp_desc) (  deleteTailSYH exprLi)) 
      | _ -> (* it is a tuple*)
        TTupple (List.map (fun a -> expressionToTerm a.pexp_desc) exprLi)  ) 
    | _ -> raise (Foo ("ai you ... helper" ^ string_of_expression_kind (exprIn) ) )


let eventToEs (ev:event) : es = 
  match ev with
  | One ins -> Singleton (Event ins)
  | Zero ins -> Singleton (NotEvent ins)
  | EvHeapOp k -> Singleton (HeapOp k)
  | EvAssert pi -> Singleton (DelayAssert pi)
  | Any -> Underline
  | StopEv -> Stop

let rec infer_handling env handler ins (current:spec) (der:es) (expr:expression): spec = 
  (*print_string ("infer_handling:" ^ string_of_es der ^ "\n");*)
  match expr.pexp_desc with 
  | Pexp_fun (_, _, _ (*pattern*), exprIn) -> 
    infer_handling env handler ins current der exprIn

(* VALUE *)   
  | Pexp_constant _
  | Pexp_construct _ 
  | Pexp_ident _ -> [(True, Emp)]
   
  | Pexp_apply (fnName, li) -> 
    let name = fnNameToString fnName in 
    (*print_string ("infer_handling-Pexp_apply:" ^ name ^ "\n"); *)

    if String.compare name "continue" == 0 then 
(* CONTINUE *)
      (*let (_, continue_value) = (List.hd (List.tl li)) in 
      let eff_value = infer_of_expression env [(True, Emp)] continue_value in 
      *)
      [(True, der)]


    else if String.compare name "perform" == 0 then 
      let eff_name = getEffName (List.hd li) in 
      let eff_arg = getEffNameArg (List.hd li) in 
      [(True, Singleton (Event (eff_name, eff_arg)))]


    else if String.compare name "Printf.printf" == 0 then [(True, Emp)]

    else 
        infer_of_expression env current (expr) 


  
    
  | Pexp_sequence (ex1, ex2) -> 

      let eff1 = infer_handling env handler ins current der ex1 in 
      let eff2 = infer_handling env handler ins (concatenateEffects current eff1) der ex2 in 
      concatenateEffects eff1 eff2


    (*match ex1.pexp_desc with
    | Pexp_apply (fnName, li) -> 
      let name = fnNameToString fnName in 
      if String.compare name "continue" == 0 then 
(* CONTINUE *)
        let (_, continue_value) = (List.hd (List.tl li)) in 
        let eff_value = infer_of_expression env [(True, Emp)] continue_value in 
        
        infer_handling env handler ins (concatenateEffects current eff_value) der ex2

  

      else if String.compare name "perform" == 0 then 
        let eff_name = getEffName (List.hd li) in 
        let eff_arg = getEffNameArg (List.hd li) in 
        List.flatten (
          List.map (fun (p, t) ->
            infer_handling env handler ins [(p, (Cons(t, Singleton (Event (eff_name, eff_arg)))))] der ex2
          ) current
        )

      
      else 
        let eff1 = infer_handling env handler ins current der ex1 in 
        infer_handling env handler ins eff1 der ex2
    | _ -> raise (Foo "not yet here")
    *)


  | Pexp_ifthenelse (_, e2, e3_op) ->  
    let branch1 = infer_handling env handler ins current der e2 in 
    (match e3_op with 
    | None -> branch1
    | Some expr3 -> 
      let branch2 = infer_handling env handler ins current der expr3 in 
      List.append branch1 branch2)

  | Pexp_assert _ -> 
    infer_of_expression env current (expr) 



  | _ -> 
    raise (Foo (string_of_expression_kind expr.pexp_desc ^ "\n\n in infer_handling \n " ^ 
    Pprintast.string_of_expression  expr ^ " infer_of_expression not corvered ")) 



and handlerCompute env (history:es) handler (p, t) : spec = 
  match (normalES t) with 
  | Stop -> 
    let (normalExpr:expression) = findNormalReturn handler in 
    infer_of_expression env [(p, history)] normalExpr
  | _ -> 
    let (fstSet:event list) = fst t in 

    List.flatten (List.map ( fun f ->
      match f with
      | One (ins) -> 
        let (effName, actualArgLi) = ins in 
        (match (findEffectHanding handler effName) with 
        | None -> 
          let ev =  eventToEs f in 
          List.map (fun (a, b)-> (a, Cons(ev, b)))  (handlerCompute env (Cons (history, ev)) handler (p, derivative t f))
        | Some (expr, formalArgLi) -> 

          let rec argumentBinder (formal:string list) (actual:(basic_t list)): (string * basic_t) list =
            match (formal, actual) with 
            | ([], []) -> []
            | (x::xs, y::ys) -> (x, y) :: argumentBinder xs ys
            | (_, _) -> raise (Foo ("argumentBinder error"))
          in 
          let pushStack = argumentBinder formalArgLi actualArgLi in 
          let () = variableStack := List.append (pushStack) !variableStack in 

        (* *)
        
          let der = (derivative t f) in 
          let continuation = handlerReasoning env handler [(p, der)] in 
          List.flatten (List.map (fun (_, a) -> 
            infer_handling env handler ins [(p, history)] (a) expr
          ) continuation)
          (*[(p, Cons(history, Singleton (Event ins)))] (derivative t f) expr *)
          
        )    
      | _ ->  
        let ev =  eventToEs f in 
        List.map (fun (a, b)-> (a, Cons(ev, b)))  (handlerCompute env (Cons (history, ev)) handler (p, derivative t f))

      
    ) fstSet)

and handlerReasoning env handler eff : spec = 
  List.flatten (List.map (fun tuple-> handlerCompute env Emp handler tuple) eff)

and infer_of_expression (env) (current:spec) expr: spec =  
  let current  = normalSpec current in 
  match expr.pexp_desc with 
  | Pexp_fun (_, _, _ (*pattern*), exprIn) -> 
    infer_of_expression env current exprIn
  | Pexp_assert exprIn -> 
    (match exprIn.pexp_desc with 
    | Pexp_apply (bop, bopLi ) -> 
        if List.length bopLi == 2 then 
          let (_,  bopLhs) = (List.hd bopLi) in 
          let (_,  bopRhs) = List.hd (List.tl bopLi) in 
          let bopLhsTerm = expressionToTerm bopLhs.pexp_desc in 
          let bopRhsTerm = expressionToTerm bopRhs.pexp_desc in 
          if String.compare (fnNameToString bop) "="  == 0 then 
          [(True, Singleton (DelayAssert (Atomic (EQ, bopLhsTerm, bopRhsTerm))))]
          else if String.compare (fnNameToString bop) ">"  == 0 then 
          [(True, Singleton (DelayAssert (Atomic (GT, bopLhsTerm, bopRhsTerm))))]
          else if String.compare (fnNameToString bop) "<"  == 0 then 
          [(True, Singleton (DelayAssert (Atomic (LT, bopLhsTerm, bopRhsTerm))))]
          else if String.compare (fnNameToString bop) ">="  == 0 then 
          [(True, Singleton (DelayAssert (Atomic (GTEQ, bopLhsTerm, bopRhsTerm))))]
          else [(True, Singleton (DelayAssert (Atomic (LTEQ, bopLhsTerm, bopRhsTerm))))]
        else 
          let (_,  bopLhs) = (List.hd bopLi) in 
          print_string ( Pprintast.string_of_expression  bopLhs^ "\n" );
          [(True, Singleton (DelayAssert(Predicate (fnNameToString bop, expressionToTerm bopLhs.pexp_desc))))]


    | _ -> raise (Foo (string_of_expression_kind (exprIn.pexp_desc) )) 
    )


(* VALUE *)
  | Pexp_constant _
  | Pexp_construct _ 
  | Pexp_ident _ -> [(True, Emp)] 
  | Pexp_sequence (ex1, ex2) -> 
  let eff1 = infer_of_expression env current ex1 in 
  let eff2 = infer_of_expression env (concatenateEffects current eff1) ex2 in 
  concatenateEffects eff1 eff2
    
(* CONDITIONAL not path sensitive so far *)
  | Pexp_ifthenelse (_, e2, e3_op) ->  
    let branch1 = infer_of_expression env current e2 in 
    (match e3_op with 
    | None -> branch1
    | Some expr3 -> 
      let branch2 = infer_of_expression env current expr3 in 
      List.append branch1 branch2)
  | Pexp_let (_(*flag*),  vb_li, let_expression) -> 
    let head = List.hd vb_li in 
    let var_name = string_of_pattern (head.pvb_pat) in 
    (match (head.pvb_expr.pexp_desc) with 
    | Pexp_apply (fnName, li) -> 
        let name = fnNameToString fnName in 
        if String.compare name "Sys.opaque_identity" == 0 then 
           let (_, allocate_argument) = (List.hd li) in 
           (match allocate_argument.pexp_desc with 
           | Pexp_apply (_, li) -> 
             let (_, constant) = (List.hd li) in 
             let pointsToTerm = expressionToTerm constant.pexp_desc in 
             let ev = (Singleton (HeapOp (PointsTo (var_name, pointsToTerm)))) in 
             let his = concatnateEffEs current ev in 
             let rest = infer_of_expression env his let_expression in 
             List.map (fun (a, b) -> (a, Cons (ev, b))) rest

             (*match constant.pexp_desc with
             | Pexp_constant (Pconst_integer (str, _)) ->
                

             | Pexp_construct (_, Some expr) -> 


             | _ -> raise (Foo (var_name ^ "\n" ^string_of_expression_kind (constant.pexp_desc)))
             *)
           | _ ->  raise (Foo (var_name ^ "\n" ^string_of_expression_kind (allocate_argument.pexp_desc)))
            )
 
        else 
        let eff = infer_of_expression env current (head.pvb_expr) in 
        let his = concatenateEffects current eff in 
        let rest = infer_of_expression env his let_expression in 
        concatenateEffects eff rest

    | _ -> raise (Foo (var_name ^ "\n" ^string_of_expression_kind (head.pvb_expr.pexp_desc) )) 
    )
    | Pexp_match (ex, case_li) -> 
      let ex_eff = normalSpec (infer_of_expression env [(True, Emp)] ex) in 
      let eff_handled = handlerReasoning env case_li (concatnateEffEs ex_eff Stop) in 
      eff_handled 


    | Pexp_apply (fnName, li) -> 
      let name = fnNameToString fnName in 
      if String.compare name "perform" == 0 then 
(* PERFORM *)
        let eff_name = getEffName (List.hd li) in 
        let eff_arg = getEffNameArg (List.hd li) in 
        [(True, Singleton (Event (eff_name, eff_arg)))]
      else if String.compare name ":=" == 0 then 
        let (_,  templhs) = (List.hd li) in 
        let (_, temprhs) = (List.hd (List.tl li)) in 
        (match (templhs.pexp_desc, temprhs.pexp_desc) with
        | (Pexp_ident id, Pexp_apply (bop, bopLi)) -> 
          let lhs = getIndentName (id.txt) in 
          let (_,  bopLhs) = (List.hd bopLi) in 
          let (_,  bopRhs) = List.hd (List.tl bopLi) in 


          let bopLhsTerm = expressionToTerm bopLhs.pexp_desc in 
          let bopRhsTerm = expressionToTerm bopRhs.pexp_desc in 
          if String.compare (fnNameToString bop) "+"  == 0 then 
          [(True, Singleton (HeapOp (PointsTo (lhs, (Plus(bopLhsTerm, bopRhsTerm))))))]
          else if String.compare (fnNameToString bop) "-"  == 0 then 
          [(True, Singleton (HeapOp (PointsTo (lhs, (Minus(bopLhsTerm, bopRhsTerm))))))]
          else [(True, Singleton (HeapOp (PointsTo (lhs, (TListAppend(bopLhsTerm, bopRhsTerm))))))]
        | (Pexp_ident id1, Pexp_ident id2) -> 

          let rec findMapping str s : string = 
            match s with 
            | [] -> str
            | (x, t) :: xs -> if String.compare x str == 0 then string_of_basic_type t else findMapping str xs 
          in 

          let lhs = getIndentName (id1.txt) in 
          let rhs = getIndentName (id2.txt) in 
          print_string (List.fold_left (fun acc (str, t) -> acc ^ "\n" ^ str ^ "->" ^ string_of_basic_type t) "" !variableStack);
          let lhs' = findMapping lhs !variableStack in 
          let rhs' = findMapping rhs !variableStack in 
          [(True, Singleton (HeapOp (PointsTo (lhs', Var rhs'))))]

        | _ -> raise (Foo ("Pexp_apply:"^ string_of_expression_kind (templhs.pexp_desc) ^ " " ^ string_of_expression_kind (temprhs.pexp_desc)))
        )

      else if String.compare name "Printf.printf" == 0 then [(True, Emp)]

      else 
        let { pre = pre  ; post = post; formals = arg_formal } =
        (* if functions are undefined, assume for now that they have the default spec *)
        match Env.find_fn name env with
        | None -> { pre = default_spec_pre; post = [default_spec_post]; formals = []}
        | Some s -> s
            in
            let vb = var_binding arg_formal (List.map (fun (_, b) -> b) li) in 
      
            let postcon' = instantiateEff (List.hd post) vb in 
            let (*precon'*) _ = instantiateEff pre vb in 
      
            (*let (res,_,  str) = printReport current precon' in 
            *)
      
            if true then postcon'
            else raise (Foo ("call_function precondition fail " ^name ^":\n" ^ "TRSstr" ^ debug_string_of_expression fnName))
          
(*
  | Pexp_let (_(*flag*),  vb_li, exprIn) -> 
    let head = List.hd vb_li in 
    let var_name = string_of_pattern (head.pvb_pat) in 
    (match (head.pvb_expr.pexp_desc) with 
    | Pexp_apply (fnName, li) -> 
      let name = fnNameToString fnName in 
      if String.compare name "perform" == 0 then 
(* PERFORM *)
        let eff_name = getEffName (List.hd li) in 
        let eff_arg = getEffNameArg (List.hd li) in 
        infer_of_expression (Env.add_stack [(var_name, (eff_name, eff_arg))] env) (List.map (fun (p, t, v)-> (p, Cons(t, Singleton (Emit (eff_name, eff_arg))), v)) current) exprIn
      else (match (retriveStack name env) with
          | Some ins -> 
(* CALL-PLACEHOLDER *)
            let (_, arg) = List.hd li in  
            (match expressionToBasicT (arg) with 
            | Some eff_arg ->  infer_of_expression env 
                  (List.map (fun (p, t, v)-> (p, Cons(t, Singleton (Await (ins, eff_arg ))), v)) current) exprIn
            | None -> raise (Foo ("Placeholder has no argument")))

          | None -> 
(* FUNCTION-CALL *)
let { pre = pre  ; post = post; formals = arg_formal } =
(* if functions are undefined, assume for now that they have the default spec *)
match Env.find_fn name env with
| None -> { pre = default_spec_pre; post = [default_spec_post]; formals = []}
| Some s -> s
      in
      let vb = var_binding arg_formal (List.map (fun (_, b) -> b) li) in 

      let postcon' = instantiateEff (List.hd post) vb in 
      let precon' = instantiateEff pre vb in 

      let (res, _, str) = printReport current precon' in 
      
      if res then concatenateEffects current postcon'
       else raise (Foo ("call_function precondition fail " ^name ^":\n" ^ str ^ debug_string_of_expression fnName))             
            )
    | _ -> raise (Foo "Let error")
    )

  | Pexp_match (ex, case_li) -> 
    let ex_eff = normalSpec (infer_of_expression env [(True, Emp, UNIT)] ex) in 
    let eff_fix = fixpoint_Computation env case_li (concatnateEffEs ex_eff Stop) in 
    concatenateEffects current eff_fix 


  
(* Aplications *)
  | Pexp_apply (fnName, li) -> 
      let name = fnNameToString fnName in 
      if String.compare name "perform" == 0 then 
(* PERFORM *)
        let eff_name = getEffName (List.hd li) in 
        let eff_arg = getEffNameArg (List.hd li) in 
        (List.map (fun (p, t, v)-> (p, Cons(t, Singleton (Emit (eff_name, eff_arg))), v)) current)
      else (match (retriveStack name env) with
          | Some ins -> 
(* CALL-PLACEHOLDER *)
            let (_, arg) = List.hd li in  
            (match expressionToBasicT (arg) with 
            | Some eff_arg ->  
                  (List.map (fun (p, t, v)-> (p, Cons(t, Singleton (Await (ins, eff_arg ))), v)) current)
            | None -> raise (Foo ("Placeholder has no argument")))

          | None -> 
(* FUNCTION-CALL *)
let { pre = pre  ; post = post; formals = arg_formal } =
(* if functions are undefined, assume for now that they have the default spec *)
match Env.find_fn name env with
| None -> { pre = default_spec_pre; post = [default_spec_post]; formals = []}
| Some s -> s
      in
      let vb = var_binding arg_formal (List.map (fun (_, b) -> b) li) in 

      let postcon' = instantiateEff (List.hd post) vb in 
      let precon' = instantiateEff pre vb in 


      let (res,_,  str) = printReport current precon' in 
      

      if res then concatenateEffects current postcon'
       else raise (Foo ("call_function precondition fail " ^name ^":\n" ^ str ^ debug_string_of_expression fnName))
            )
*)

  | _ -> raise (Foo (string_of_expression_kind expr.pexp_desc ^ "\n\n" ^ 
    Pprintast.string_of_expression  expr ^ " infer_of_expression not corvered ")) 
    
and normalSpecList specs = List.map (fun a -> normalSpec a) specs

and infer_value_binding rec_flag env vb =
  let fn_name = string_of_pattern vb.pvb_pat in
  let body = vb.pvb_expr in
  let formals = collect_param_names body in
  match function_spec body with
  | None -> None (*default_spec_pre, [default_spec_post]*)
  | Some (pre, post) -> 
  let spec = (normalSpec pre, normalSpecList post) in 
  let (pre, post) = spec in

  (*let env = Env.reset_side_spec pre_side env in  *)
  let env =
    match rec_flag with
    | Nonrecursive -> env
    | Recursive -> 
      Env.add_fn fn_name {pre; post; formals} env
  in

  let final =  (infer_of_expression env pre body) in

  let final = normalSpec final in 


(*
        (*SYH-11: This is because Prof Chin thinks the if the precondition is all the trace, it is not modular*)
        let (pre_p, pre_es, pre_side) = precon in 
        let precon = (pre_p, Cons (Kleene (Underline),pre_es), pre_side) in 
        *)

  let env1 = Env.add_fn fn_name { pre; post; formals } env in
  

  Some (pre, post, ( final), env1, fn_name)



type experiemntal_data = (float list * float list) 


let infer_of_value_binding rec_flag env vb: string * env * experiemntal_data =
  let startTimeStamp = Sys.time() in
  match  infer_value_binding rec_flag env vb with 
  | None -> "", env, ([], [])
  | Some (pre, post, final, env, fn_name) -> 

  (* don't report things like let () = ..., which isn't a function  *)
  if String.equal fn_name "()" then
    "", env, ([], [])
  else


    let header =
      "\n========== Function: "^ fn_name ^" ==========\n" ^
      "[Pre  Condition] " ^ string_of_spec pre ^"\n"^
      "[Post Condition] " ^ string_of_spec (List.hd post) ^"\n"^
      (let infer_time = "[Inference Time: " ^ string_of_float ((Sys.time() -. startTimeStamp) *. 1000.0) ^ " ms]" in
      (*let (_, _, trs_str) = printReport final (concatenateEffects pre (List.hd post)) in
*)
      "[Final  Effects] " ^ string_of_spec (normalSpec final) ^ "\n"^ infer_time ^ "\n" ^ "trs_str" ^"\n")
      (*(string_of_inclusion final_effects post) ^ "\n" ^*)
      (*"[T.r.s: Verification for Post Condition]\n" ^ *)
    (*in
    
    let ex_res = List.fold_left (fun (succeed_time, fail_time) a -> 
      let (res, time, _) = printReport final a in 
      if res then (List.append [time]  succeed_time, fail_time)
      else (succeed_time, List.append [time]  fail_time)
      ) ([], []) post 
      *)
    in header , env, ([], [])


  (*

  let attributes = vb.pvb_attributes in 
  string_of_attributes attributes ^ "\n"
  *)


(* returns the inference result as a string to be printed *)
let rec infer_of_program env x: string * env * experiemntal_data =
  match x.pstr_desc with
  | Pstr_value (rec_flag, x::_ (*value_binding list*)) ->
    infer_of_value_binding rec_flag env x
    
  | Pstr_module m ->
    (* when we see a module, infer inside it *)
    let name = m.pmb_name.txt |> Option.get in
    let res, menv, _ =
      match m.pmb_expr.pmod_desc with
      | Pmod_structure str ->
        List.fold_left (fun (s, env, aaaa) si ->
          let r, env, _ = infer_of_program env si in
          r :: s, env, aaaa) ([], env, ([], [])) str
      | _ -> failwith "infer_of_program: unimplemented module expression type"
    in
    let res = String.concat "\n" (Format.sprintf "--- Module %s---" name :: res) in
    let env1 = Env.add_module name menv env in
    res, env1, ([], [])

  | Pstr_open info ->
    (* when we see a structure item like: open A... *)
    let name =
      match info.popen_expr.pmod_desc with
      | Pmod_ident name ->
      begin match name.txt with
      | Lident s -> s
      | _ -> failwith "infer_of_program: unimplemented open type, can only open names"
      end
      | _ -> failwith "infer_of_program: unimplemented open type, can only open names"
    in
    (* ... dump all the bindings in that module into the current environment and continue *)
    "", Env.open_module name env,  ([], [])

  | Pstr_effect { peff_name; peff_kind; _ } ->
    begin match peff_kind with
    | Peff_decl (args, res) ->
      (* converts a type of the form a -> b -> c into ([a, b], c) *)
      let split_params_fn t =
        let rec loop acc t =
          match t.ptyp_desc with
          | Ptyp_arrow (_, a, b) ->
            (* note that we don't recurse in a *)
            loop (a :: acc) b
          | Ptyp_constr ({txt=Lident "int"; _}, [])
          | Ptyp_constr ({txt=Lident "string"; _}, []) 
          | Ptyp_constr ({txt=Lident "unit"; _}, []) -> List.rev acc, t
          | _ -> failwith ("split_params_fn: " ^ debug_string_of_core_type t)
        in loop [] t
      in
      let name = peff_name.txt in
      let params = List.map core_type_to_typ args in
      let res = split_params_fn res
        |> (fun (a, b) -> (List.map core_type_to_typ a, core_type_to_typ b)) in
      let def = { params; res } in
      "", Env.add_effect name def env, ([], [])
    | Peff_rebind _ -> failwith "unsupported effect spec rebind"
    end
  | _ ->  string_of_es Bot, env,  ([], [])
  ;;


let debug_tokens str =
  let lb = Lexing.from_string str in
  let rec loop tokens =
    let tok = Lexer.token lb in
    match tok with
    | EOF -> List.rev (tok :: tokens)
    | _ -> loop (tok :: tokens)
  in
  let tokens = loop [] in
  let s = tokens |> List.map Debug.string_of_token |> String.concat " " in
  Format.printf "%s@." s



let () =
  let inputfile = (Sys.getcwd () ^ "/" ^ Sys.argv.(1)) in
(*    let outputfile = (Sys.getcwd ()^ "/" ^ Sys.argv.(2)) in
print_string (inputfile ^ "\n" ^ outputfile^"\n");*)
  let ic = open_in inputfile in
  try
      let lines =  (input_lines ic ) in
      let line = List.fold_right (fun x acc -> acc ^ "\n" ^ x) (List.rev lines) "" in
      
      (* debug_tokens line; *)

      let progs = Parser.implementation Lexer.token (Lexing.from_string line) in

      
      (* Dump AST -dparsetree-style *)
      (* Format.printf "%a@." Printast.implementation progs; *)

      (*print_string (Pprintast.string_of_structure progs ) ; 
      print_endline (List.fold_left (fun acc a -> acc ^ "\n" ^ string_of_program a) "" progs);

      *)

      let results, _ , ex_res=
        List.fold_left (fun (s, env, (aaa, bbb)) a ->
          let spec, env1, (aa, bb) = infer_of_program env a in
          spec :: s, env1, (List.append aaa aa, List.append bbb bb)
        ) ([], Env.empty, ([], [])) progs
      in
      let print_summary li = 
        string_of_float ((List.fold_left (fun acc a -> acc +. a) 0.0 li) /. (float_of_int (List.length li) )) ^ " out of " ^ 
        string_of_int  (List.length li) ^" test case(s) \n" in 
      let (yeah, ohhh) = ex_res in 
      let (yeah_number, ohhh_number) = (print_summary yeah, print_summary ohhh) in 
       
      print_endline (results |> List.rev |> String.concat "");

      print_endline ("Average Proving Time (ms) is " ^ yeah_number ^ "Average DisProving Time (ms) is " ^ ohhh_number );


      (* 
      print_endline (testSleek ());

      *)
      (*print_endline (Pprintast.string_of_structure progs ) ; 
      print_endline ("---");
      print_endline (List.fold_left (fun acc a -> acc ^ forward a) "" progs);*)
      flush stdout;                (* 现在写入默认设备 *)
      close_in ic                  (* 关闭输入通道 *)

    with
    | Pretty.Foo s ->
      print_endline "\nERROR:\n";
      print_endline s
    | e ->                      (* 一些不可预见的异常发生 *)
      close_in_noerr ic;           (* 紧急关闭 *)
      raise e                      (* 以出错的形式退出: 文件已关闭,但通道没有写入东西 *)

   ;;

