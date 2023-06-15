open Hiptypes
open Pretty
open Infer_types
open Normalize

(** A write-only list that supports efficient accumulation from the back *)
module Acc : sig
  type 'a t

  val empty : 'a t
  val add : 'a -> 'a t -> 'a t
  val add_all : 'a list -> 'a t -> 'a t
  val to_list : 'a t -> 'a list
end = struct
  type 'a t = 'a list

  let empty = []
  let add = List.cons
  let add_all xs t = List.fold_left (Fun.flip List.cons) t xs
  let to_list = List.rev
end

let string_of_pi p = string_of_pi (ProversEx.normalize_pure p)
let rename_exists_spec sp = List.hd (Forward_rules.renamingexistientalVar [sp])

let rename_exists_lemma (lem : lemma) : lemma =
  {
    lem with
    l_left = rename_exists_spec lem.l_left;
    l_right = rename_exists_spec lem.l_right;
  }

exception Unification_failure

let match_lemma :
    string list -> lemma -> spec -> ((string * term) list * spec * spec) option
    =
 (* let ( let* ) = Option.bind in *)
 fun bound lem sp ->
  let les, _ln = normalise_spec lem.l_left in
  (* let lr = Pretty.normalise_spec lem.l_right in *)
  let ses, sn = normalise_spec sp in
  (* collects bindings in bs, prefix is the prefix of s that is not matched, ret is the return value of the last matched state of ses, goes down les and ses in parallel, until les is empty (fully matched). fails if ses becomes empty while les isn't *)
  let rec loop prefix bs les ses =
    (* Format.printf "loop %s %s@."
       (string_of_list (fun l -> fst l.e_constr) les)
       (string_of_list (fun l -> fst l.e_constr) ses); *)
    match (les, ses) with
    | [], [] ->
      (* TODO how should we check if the normal stage is matched? since we only match functions and arguments *)
      Some
        ( bs,
          Acc.to_list prefix,
          [ (* (let _, _, (p, h), r = sn in
               NormalReturn (p, h, r)); *) ] )
    | [], _ ->
      (* match normal states *)
      (* Format.printf "!!! %s@." (string_of_option string_of_term ret); *)
      (* if a match occurred, there has to be a value *)
      (* let* r = ret in *)
      (* Option.bind ret (fun r -> ) *)
      Some (bs, Acc.to_list prefix, normalisedStagedSpec2Spec (ses, sn))
    | _ :: _, [] ->
      (* we still have more effect stages but nothing to match against, so a match is impossible now *)
      None
    | l1 :: les1, s1 :: ses1 ->
      (* matching is only done on constructors. other fields (state) probably have to be matched also but may require proof. not yet needed. also we probably shouldn't be invoking a prover for this, coq uses norm then syntactic equality to unify *)
      (* https://coq.inria.fr/refman/proof-engine/tactics.html#coq:tacn.apply *)
      let lcons, largs = l1.e_constr in
      let scons, sargs = s1.e_constr in
      let matched =
        String.equal lcons scons && List.compare_lengths largs sargs = 0
      in
      (match matched with
      | false ->
        (* try to find a match lower down *)
        (* TODO we should forget bindings when this happens *)
        (* Format.printf "cannot match@."; *)
        loop
          (Acc.add_all
             (normalisedStagedSpec2Spec ([s1], freshNormalStage))
             prefix)
          bs les ses1
      | true ->
        (* Format.printf "found match %s@." scons; *)
        (* we found a match. unify, get substitution, check it, then continue matching *)
        (try
           let bs1 =
             List.map2
               (fun a1 a2 -> (a1, a2))
               (l1.e_ret :: largs) (s1.e_ret :: sargs)
             |> List.filter_map (function
                  | Var l, s when List.mem l bound -> Some (l, s)
                  | _ -> None)
           in
           (* alpha conversion: binders are equal up to renaming *)
           (* https://coq.inria.fr/refman/language/core/conversion.html *)
           (* let bs =
                match (l1.e_ret, s1.e_ret) with
                | Var vl, Var vs
                  when List.mem vl l1.e_evars && List.mem vs s1.e_evars ->
                  (vl, Var vs) :: bs
                | _ -> bs
              in *)
           (* TODO check if the bindings to the same name agree. if not, fail unification *)
           (* && match List.assoc_opt a acc with
                                   | None -> true
                                   | Some c when c = b -> false
                                   | Some _ -> raise Unification_failure *)
           (* matched, so don't add to the prefix *)
           let p, h = s1.e_post in
           loop
             (Acc.add_all [Exists s1.e_evars; NormalReturn (p, h, UNIT)] prefix)
             (bs1 @ bs) les1 ses1
         with Unification_failure -> None))
  in
  loop Acc.empty [] les ses

let instantiate_res_existential lem =
  let _, (_, _, _, lret) = normalise_spec lem.l_left in
  let _, (_, _, _, rret) = normalise_spec lem.l_right in
  match (lret, rret) with
  | Var l, Var r ->
    {
      lem with
      l_right = Forward_rules.instantiateSpec [(r, Var l)] lem.l_right;
    }
  | _ -> lem

(** To use a lemma for rewriting, e.g. using l = (N1;N2 <: N3) to rewrite goal N0;N1;N2;N4 to N0;N3;N4, we match l against the goal by unifying segments (prefix=N0, suffix=N4), collecting bindings for universally-quantified variables, then replacing that portion of the goal once the match is complete. *)
let apply_lemma : lemma -> spec -> spec =
 fun lem sp ->
  (* Format.printf "lem1 %s@." (string_of_lemma lem); *)
  let lem = rename_exists_lemma lem in
  (* Format.printf "lem2 %s@." (string_of_lemma lem); *)
  (* let lem = instantiate_res_existential lem in *)
  match match_lemma lem.l_params lem sp with
  | None -> sp (* must be == *)
  | Some (bs, prefix, suffix) ->
    let inst_lem_rhs =
      List.map (Forward_rules.instantiateStages bs) lem.l_right
    in
    let inst_lem_rhs =
      (* add an extra equality between the return value and the variable it gets bound to outside *)
      (* let _, (_, _, _, ret1) = normalise_spec inst_lem_rhs in
         (* let _, (_, _, _, ret2) = normalise_spec sp in *)
         NormalReturn (Atomic (EQ, ret1, ret2), EmptyHeap, UNIT) :: *)
      (* shouldn't always add *)
      inst_lem_rhs
    in
    info ~title:"apply_lemma" "bindings: %s\nprefix: %s\nsuffix: %s\nrhs: %s"
      (string_of_instantiations string_of_term bs)
      (string_of_spec prefix) (string_of_spec suffix)
      (string_of_list string_of_staged_spec inst_lem_rhs);
    let substituted : spec = prefix @ inst_lem_rhs @ suffix in
    substituted

let apply_one_lemma : lemma list -> spec -> spec * lemma option =
 fun lems sp ->
  List.fold_left
    (fun (sp, app) l ->
      match app with
      | Some _ -> (sp, app)
      | None ->
        let sp1 = apply_lemma l sp in
        if sp1 == sp then (sp, app) else (sp1, Some l))
    (sp, None) lems

let instantiate_pred : pred_def -> term list -> term -> pred_def =
 fun pred args ret ->
  (* the predicate should have one more arg than arguments given for the return value, which we'll substitute with the return term from the caller *)
  let params, ret_param = split_last pred.p_params in
  let bs = (ret_param, ret) :: List.map2 (fun a b -> (a, b)) params args in
  {
    pred with
    p_body =
      List.map
        (fun b -> List.map (Forward_rules.instantiateStages bs) b)
        pred.p_body;
  }

module Heap = struct
  let normalize : state -> state =
   fun (p, h) ->
    let h = normaliseHeap h in
    (ProversEx.normalize_pure p, h)

  (** given a nonempty heap formula, splits it into a points-to expression and another heap formula *)
  let rec split_one : kappa -> ((string * term) * kappa) option =
   fun h ->
    match h with
    | EmptyHeap -> None
    | PointsTo (x, v) -> Some ((x, v), EmptyHeap)
    | SepConj (a, b) -> begin
      match split_one a with
      | None -> split_one b
      | Some (c, r) -> Some (c, SepConj (r, b))
    end

  (** like split_one, but searches for a particular points-to *)
  let rec split_find : string -> kappa -> (term * kappa) option =
   fun n h ->
    match h with
    | EmptyHeap -> None
    | PointsTo (x, v) when x = n -> Some (v, EmptyHeap)
    | PointsTo _ -> None
    | SepConj (a, b) -> begin
      match split_find n a with
      | None ->
        split_find n b |> Option.map (fun (t, b1) -> (t, SepConj (a, b1)))
      | Some (t, a1) -> Some (t, SepConj (a1, b))
    end

  let pairwise_var_inequality v1 v2 =
    List.concat_map
      (fun x ->
        List.filter_map
          (fun y ->
            if String.equal x y then None
            else Some (Not (Atomic (EQ, Var x, Var y))))
          v2)
      v1
    |> conj

  let xpure : kappa -> pi =
   fun h ->
    let rec run h =
      match h with
      | EmptyHeap -> (True, [])
      | PointsTo (x, _t) -> (Atomic (GT, Var x, Num 0), [x])
      | SepConj (a, b) ->
        let a, v1 = run a in
        let b, v2 = run b in
        (And (a, And (b, pairwise_var_inequality v1 v2)), [])
    in
    let p, _vs = run h in
    p
end

let check_staged_entail : spec -> spec -> spec option =
 fun n1 n2 ->
  let norm = normalise_spec (n1 @ n2) in
  Some (normalisedStagedSpec2Spec norm)

let instantiate_state bindings (p, h) =
  ( Forward_rules.instantiatePure bindings p,
    Forward_rules.instantiateHeap bindings h )

let instantiate_existentials_effect_stage bindings =
  let names = List.map fst bindings in
  fun eff ->
    {
      eff with
      e_evars = List.filter (fun v -> not (List.mem v names)) eff.e_evars;
      e_pre = instantiate_state bindings eff.e_pre;
      e_post = instantiate_state bindings eff.e_post;
      e_constr =
        ( fst eff.e_constr,
          List.map (Forward_rules.instantiateTerms bindings) (snd eff.e_constr)
        );
      e_ret = Forward_rules.instantiateTerms bindings eff.e_ret;
    }

(** actually instantiates existentials, vs what the forward rules version does *)
let instantiate_existentials :
    (string * term) list -> normalisedStagedSpec -> normalisedStagedSpec =
 fun bindings (efs, ns) ->
  let names = List.map fst bindings in
  let efs1 = List.map (instantiate_existentials_effect_stage bindings) efs in
  let ns1 =
    let vs, pre, post, ret = ns in
    ( List.filter (fun v -> not (List.mem v names)) vs,
      instantiate_state bindings pre,
      instantiate_state bindings post,
      Forward_rules.instantiateTerms bindings ret )
  in
  (efs1, ns1)

let freshen_existentials vs state =
  let vars_fresh =
    List.map (fun v -> (v, Var (verifier_getAfreeVar ~from:v ()))) vs
  in
  (vars_fresh, instantiate_state vars_fresh state)

let ( let@ ) f x = f x

open Res.Option

(** Given two heap formulae, matches points-to predicates.
  may backtrack if the locations are quantified.
  returns (by invoking the continuation) when matching is complete (when right is empty).

  id: human-readable name
  vs: quantified variables
  k: continuation
*)
let rec check_qf :
    string ->
    string list ->
    state ->
    state ->
    (pi * pi -> 'a option) ->
    'a option =
 fun id vs ante conseq k ->
  (* TODO ptr equalities? *)
  let a = Heap.normalize ante in
  let c = Heap.normalize conseq in
  debug ~title:"SL entailment" "%s |- %s" (string_of_state ante)
    (string_of_state conseq);
  match (a, c) with
  | (p1, h1), (p2, EmptyHeap) ->
    let left = And (Heap.xpure h1, p1) in
    k (left, p2)
  | (p1, h1), (p2, h2) -> begin
    (* we know h2 is non-empty *)
    match Heap.split_one h2 with
    | Some ((x, v), h2') when List.mem x vs ->
      let left_heap = list_of_heap h1 in
      (match left_heap with
      | [] -> None
      | _ :: _ ->
        (* x is bound and could potentially be instantiated with anything on the right side, so try everything *)
        let r1 =
          any
            ~to_s:(fun (a, _) -> string_of_pair Fun.id string_of_term a)
            ~name:"ent-match-any"
            (left_heap |> List.map (fun a -> (a, (x, v))))
            (fun ((x1, v1), _) ->
              let _v2, h1' = Heap.split_find x1 h1 |> Option.get in
              (* ptr equality *)
              let _ptr_eq = Atomic (EQ, Var x1, Var x) in
              let triv = Atomic (EQ, v, v1) in
              (* matching ptr values are added as an eq to the right side, since we don't have a term := term substitution function *)
              check_qf id vs (conj [p1], h1') (conj [p2; triv], h2') k)
        in
        r1)
    | Some ((x, v), h2') -> begin
      (* x is free. match against h1 exactly *)
      match Heap.split_find x h1 with
      | Some (v1, h1') -> begin
        check_qf (*  *) id vs
          (conj [p1], h1')
          (conj [p2; And (p1, Atomic (EQ, v, v1))], h2')
          k
      end
      | None -> None
    end
    | None -> failwith (Format.asprintf "could not split LHS, bug?")
  end

let with_pure pi ((p, h) : state) : state = (conj [p; pi], h)

let rec unfold_predicate_aux pred prefix (s : spec) : disj_spec =
  match s with
  | [] -> List.map Acc.to_list prefix
  | HigherOrder (p, h, (name, args), ret) :: s1
    when String.equal name pred.p_name ->
    info
      ~title:(Format.asprintf "unfolding: %s" name)
      "%s" (string_of_pred pred);
    let pred1 = instantiate_pred pred args ret in
    let prefix =
      prefix
      |> List.concat_map (fun p1 ->
             List.map
               (fun disj ->
                 p1 |> Acc.add (NormalReturn (p, h, UNIT)) |> Acc.add_all disj)
               pred1.p_body)
    in
    unfold_predicate_aux pred prefix s1
  | c :: s1 ->
    let pref = List.map (fun p -> Acc.add c p) prefix in
    unfold_predicate_aux pred pref s1

(** f;a;e \/ b and a == c \/ d
  => f;(c \/ d);e \/ b
  => f;c;e \/ f;d;e \/ b *)
let unfold_predicate : pred_def -> disj_spec -> disj_spec =
 fun pred ds ->
  List.concat_map (fun s -> unfold_predicate_aux pred [Acc.empty] s) ds

let unfold_predicate_spec : pred_def -> spec -> disj_spec =
 fun pred sp -> unfold_predicate_aux pred [Acc.empty] sp

let unfold_predicate_norm :
    pred_def -> normalisedStagedSpec -> normalisedStagedSpec list =
 fun pred sp ->
  List.map normalise_spec
    (unfold_predicate_spec pred (normalisedStagedSpec2Spec sp))

let spec_function_names (spec : spec) =
  List.concat_map
    (function HigherOrder (_, _, (f, _), _) -> [f] | _ -> [])
    spec
  |> SSet.of_list

(** proof context *)
type pctx = {
  lems : lemma list;
  preds : pred_def SMap.t;
  (* all quantified variables in this formula *)
  q_vars : string list;
  (* predicates which have been unfolded, used as an approximation of progress (in the cyclic proof sense) *)
  unfolded : string list;
  (* lemmas applied *)
  applied : string list;
}

let string_of_pctx ctx =
  Format.asprintf
    "lemmas: %s\npredicates: %s\nq_vars: %s\nunfolded: %s\napplied: %s@."
    (string_of_list string_of_lemma ctx.lems)
    (string_of_smap string_of_pred ctx.preds)
    (string_of_list Fun.id ctx.q_vars)
    (string_of_list Fun.id ctx.unfolded)
    (string_of_list Fun.id ctx.applied)

let default_pctx lems preds q_vars =
  { lems; preds; q_vars; unfolded = []; applied = [] }

(** Recurses down a normalised staged spec, matching stages,
   translating away heap predicates to build a pure formula,
   and proving subsumption of each pair of stages.
   Residue from previous stages is assumed.

   Matching of quantified locations may cause backtracking.
   Other quantifiers are left to z3 to instantiate.
   
   i: index of stage
   all_vars: all quantified variables
*)
let rec check_staged_subsumption_aux :
    pctx ->
    int ->
    pi ->
    normalisedStagedSpec ->
    normalisedStagedSpec ->
    unit option =
 fun ctx i assump s1 s2 ->
  info ~title:"subsumption" "%s\n<:\n%s"
    (string_of_normalisedStagedSpec s1)
    (string_of_normalisedStagedSpec s2);
  match (s1, s2) with
  | (es1 :: es1r, ns1), (es2 :: es2r, ns2) ->
    (* fail fast by doing easy checks first *)
    let c1, a1 = es1.e_constr in
    let c2, a2 = es2.e_constr in
    (match String.equal c1 c2 with
    | false ->
      let@ _ =
        try_other_measures ctx s1 s2 None (Some c2) i assump |> or_else
      in
      info ~title:"FAIL" "constr %s != %s" c1 c2;
      fail
      (* try to unfold the right side, then the left *)
      (* (match List.find_opt (fun p -> String.equal c2 p.p_name) ctx.preds with
         | Some def when not (List.mem c2 ctx.unfolded) ->
           let unf = unfold_predicate_norm def s2 in
           let@ s2_1 = any ~name:"?" ~to_s:string_of_normalisedStagedSpec unf in
           check_staged_subsumption_aux
             { ctx with unfolded = c2 :: ctx.unfolded }
             i assump s1 s2_1
         | _ ->
           (match List.find_opt (fun p -> String.equal c1 p.p_name) ctx.preds with
           | Some def when not (List.mem c1 ctx.unfolded) ->
             let unf = unfold_predicate_norm def s1 in
             let@ s1_1 = all ~to_s:string_of_normalisedStagedSpec unf in
             check_staged_subsumption_aux
               { ctx with unfolded = c1 :: ctx.unfolded }
               i assump s1_1 s2
           | _ ->
             (* try to apply a lemma *)
             let eligible =
               ctx.lems
               |> List.filter (fun l -> List.mem l.l_name ctx.unfolded)
               |> List.filter (fun l -> not (List.mem l.l_name ctx.applied))
             in
             let s1_1, applied =
               apply_one_lemma eligible (normalisedStagedSpec2Spec s1)
             in
             (match applied with
             | Some app ->
               check_staged_subsumption_aux
                 { ctx with applied = app :: ctx.unfolded }
                 i assump (normalise_spec s1_1) s2
             | None ->
               (* no predicates to try unfolding *)
               info "FAIL, constr %s != %s" c1 c2;
               fail))) *)
    | true ->
      let* _ =
        let l1 = List.length a1 in
        let l2 = List.length a2 in
        let r = l1 = l2 in
        if not r then (
          info ~title:"FAIL" "arg length %s (%d) != %s (%d)"
            (string_of_list string_of_term a1)
            l1
            (string_of_list string_of_term a2)
            l2;
          fail)
        else ok
      in
      let* residue =
        let arg_eqs = conj (List.map2 (fun x y -> Atomic (EQ, x, y)) a1 a2) in
        stage_subsumes ctx
          (Format.asprintf "Eff %d" i)
          assump
          (es1.e_evars, (es1.e_pre, es1.e_post, es1.e_ret))
          (es2.e_evars, (es2.e_pre, with_pure arg_eqs es2.e_post, es2.e_ret))
      in
      check_staged_subsumption_aux ctx (i + 1)
        (conj [assump; residue])
        (es1r, ns1) (es2r, ns2))
  | ([], ns1), ([], ns2) ->
    (* base case: check the normal stage at the end *)
    let (vs1, (p1, h1), (qp1, qh1), r1), (vs2, (p2, h2), (qp2, qh2), r2) =
      (ns1, ns2)
    in
    let* _residue =
      stage_subsumes ctx "Norm" assump
        (vs1, ((p1, h1), (qp1, qh1), r1))
        (vs2, ((p2, h2), (qp2, qh2), r2))
    in
    ok
  | ([], _), (es2 :: _, _) ->
    let c2, _ = es2.e_constr in
    let@ _ = try_other_measures ctx s1 s2 None (Some c2) i assump |> or_else in
    (* try to unfold predicates *)
    (* (match List.find_opt (fun p -> String.equal c2 p.p_name) ctx.preds with
       | Some def when not (List.mem c2 ctx.unfolded) ->
         let unf = unfold_predicate_norm def s2 in
         let@ s2_1 = any ~name:"?" ~to_s:string_of_normalisedStagedSpec unf in
         check_staged_subsumption_aux
           { ctx with unfolded = c2 :: ctx.unfolded }
           i assump s1 s2_1
       | _ -> *)
    info ~title:"FAIL" "ante is shorter\n%s\n<:\n%s"
      (string_of_normalisedStagedSpec s1)
      (string_of_normalisedStagedSpec s2);
    fail
  | (es1 :: _, _), ([], _) ->
    (* try to unfold predicates *)
    let c1, _ = es1.e_constr in
    let@ _ = try_other_measures ctx s1 s2 (Some c1) None i assump |> or_else in
    (* match List.find_opt (fun p -> String.equal c1 p.p_name) ctx.preds with
       | Some def when not (List.mem c1 ctx.unfolded) ->
         let unf = unfold_predicate_norm def s1 in
         let@ s1_1 = all ~to_s:string_of_normalisedStagedSpec unf in
         check_staged_subsumption_aux
           { ctx with unfolded = c1 :: ctx.unfolded }
           i assump s1 s1_1
       | _ -> *)
    info ~title:"FAIL" "conseq is shorter\n%s\n<:\n%s"
      (string_of_normalisedStagedSpec s1)
      (string_of_normalisedStagedSpec s2);
    fail

and try_other_measures :
    pctx ->
    normalisedStagedSpec ->
    normalisedStagedSpec ->
    string option ->
    string option ->
    int ->
    pi ->
    unit option =
 fun ctx s1 s2 c1 c2 i assump ->
  (* first try to unfold on the right *)
  match
    let* c2 = c2 in
    let+ res = SMap.find_opt c2 ctx.preds in
    (c2, res)
  with
  | Some (c2, def) when not (List.mem c2 ctx.unfolded) ->
    let unf = unfold_predicate_norm def s2 in
    if List.length unf > 1 then
      info ~title:"after unfolding (right)" "%s\n<:\n%s"
        (string_of_normalisedStagedSpec s1)
        (string_of_disj_spec (List.map normalisedStagedSpec2Spec unf));
    let@ s2_1 = any ~name:"?" ~to_s:string_of_normalisedStagedSpec unf in
    check_staged_subsumption_aux
      { ctx with unfolded = c2 :: ctx.unfolded }
      i assump s1 s2_1
  | _ ->
    (* if that fails, unfold on the left *)
    (match
       let* c1 = c1 in
       let+ res = SMap.find_opt c1 ctx.preds in
       (c1, res)
     with
    | Some (c1, def) when not (List.mem c1 ctx.unfolded) ->
      let unf = unfold_predicate_norm def s1 in
      if List.length unf > 1 then
        info ~title:"after unfolding (left)" "%s\n<:\n%s"
          (string_of_disj_spec (List.map normalisedStagedSpec2Spec unf))
          (string_of_normalisedStagedSpec s2);
      let@ s1_1 = all ~to_s:string_of_normalisedStagedSpec unf in
      check_staged_subsumption_aux
        { ctx with unfolded = c1 :: ctx.unfolded }
        i assump s1_1 s2
    | _ ->
      (* if that fails, try to apply a lemma *)
      let eligible =
        ctx.lems
        |> List.filter (fun l ->
               SSet.for_all
                 (fun n -> List.mem n ctx.unfolded)
                 (spec_function_names l.l_left))
        |> List.filter (fun l -> not (List.mem l.l_name ctx.applied))
      in
      let s1_1, applied =
        apply_one_lemma eligible (normalisedStagedSpec2Spec s1)
      in
      applied
      |> Option.iter (fun l ->
             info
               ~title:(Format.asprintf "applied: %s" l.l_name)
               "%s\n\nafter:\n%s\n<:\n%s" (string_of_lemma l)
               (string_of_spec s1_1)
               (string_of_normalisedStagedSpec s2));
      (match applied with
      | Some app ->
        check_staged_subsumption_aux
          { ctx with applied = app.l_name :: ctx.unfolded }
          i assump (normalise_spec s1_1) s2
      | None ->
        (* no predicates to try unfolding *)
        info
          ~title:
            (Format.asprintf
               "ran out of tricks to make constructors %s and %s match"
               (string_of_option Fun.id c1)
               (string_of_option Fun.id c2))
          "%s" (string_of_pctx ctx);
        fail))

and stage_subsumes :
    pctx ->
    string ->
    pi ->
    (state * state * term) quantified ->
    (state * state * term) quantified ->
    pi option =
 fun ctx what assump s1 s2 ->
  let vs1, (pre1, post1, ret1) = s1 in
  let vs2, (pre2, post2, ret2) = s2 in
  (* TODO replace uses of all_vars. this is for us to know if locations on the rhs are quantified. a smaller set of vars is possible *)
  info
    ~title:(Format.asprintf "(%s)" what)
    "%s * (%sreq %s; ens %s) <: (%sreq %s; ens %s)" (string_of_pi assump)
    (string_of_existentials vs1)
    (string_of_state pre1) (string_of_state post1)
    (string_of_existentials vs2)
    (string_of_state pre1) (string_of_state post2);
  (* contravariance *)
  let@ pre_l, pre_r = check_qf "pren" ctx.q_vars pre2 pre1 in
  let* assump, tenv =
    let left = conj [assump; pre_l] in
    let right = pre_r in
    let tenv =
      let env = create_abs_env () in
      let env = infer_types_pi env left in
      let env = infer_types_pi env right in
      env
    in
    let pre_res =
      Provers.entails_exists (concrete_type_env tenv) left vs1 right
    in
    info
      ~title:(Format.asprintf "(%s pre)" what)
      "%s => %s%s ==> %s" (string_of_pi left)
      (string_of_existentials vs1)
      (string_of_pi right) (string_of_res pre_res);
    if pre_res then Some (conj [pre_l; pre_r; assump], tenv) else None
  in
  (* covariance *)
  let new_univ = SSet.union (used_vars_pi pre_l) (used_vars_pi pre_r) in
  let vs22 = List.filter (fun v -> not (SSet.mem v new_univ)) vs2 in
  (* let res_v = verifier_getAfreeVar ~from:"res" () in *)
  let@ post_l, post_r = check_qf "postn" ctx.q_vars post1 post2 in
  let* residue =
    (* Atomic (EQ, Var res_v, ret1) *)
    (* Atomic (EQ, Var res_v, ret2) *)
    (* don't use fresh variable for the ret value so it carries forward in the residue *)
    let left = conj [assump; post_l] in
    let right = conj [post_r; Atomic (EQ, ret1, ret2)] in
    let tenv =
      let env = infer_types_pi tenv left in
      let env = infer_types_pi env right in
      env
    in
    let post_res =
      Provers.entails_exists (concrete_type_env tenv) left vs22 right
    in
    info
      ~title:(Format.asprintf "(%s post)" what)
      "%s => %s%s ==> %s" (string_of_pi left)
      (string_of_existentials vs22)
      (string_of_pi right) (string_of_res post_res);
    if post_res then Some (conj [right; assump]) else None
  in
  pure residue

let extract_binders spec =
  let binders, rest =
    List.partition_map (function Exists vs -> Left vs | s -> Right s) spec
  in
  (List.concat binders, rest)

let rec apply_tactics ts lems preds (ds1 : disj_spec) (ds2 : disj_spec) =
  List.fold_left
    (fun t c ->
      let ds1, ds2 = t in
      let r =
        match c with
        | Unfold_right ->
          info ~title:"unfold left" "%s" ((string_of_smap string_of_pred) preds);
          let ds2 = SMap.fold (fun _n -> unfold_predicate) preds ds2 in
          (ds1, ds2)
        | Unfold_left ->
          info ~title:"unfold left" "%s" (string_of_smap string_of_pred preds);
          let ds1 = SMap.fold (fun _n -> unfold_predicate) preds ds1 in
          (ds1, ds2)
        | Case (i, ta) ->
          (* case works on the left only *)
          info ~title:"case" "%d" i;
          let ds, _ = apply_tactics [ta] lems preds [List.nth ds1 i] ds2 in
          (* unfolding (or otherwise adding disjuncts) inside case will break use of hd *)
          let ds11 = replace_nth i (List.hd ds) ds1 in
          (ds11, ds2)
        | Apply l ->
          (* apply works on the left only *)
          info ~title:"apply" "%s" l;
          ( List.map
              (List.fold_right apply_lemma
                 (List.filter (fun le -> String.equal le.l_name l) lems))
              ds1,
            ds2 )
      in
      info ~title:"after" "%s\n<:\n%s"
        (string_of_disj_spec (fst r))
        (string_of_disj_spec (snd r));
      r)
    (ds1, ds2) ts

let check_staged_subsumption :
    lemma list -> pred_def SMap.t -> spec -> spec -> unit option =
 fun lems preds n1 n2 ->
  let es1, ns1 = normalise_spec n1 in
  let es2, ns2 = normalise_spec n2 in
  let q_vars =
    Forward_rules.getExistientalVar (es1, ns1)
    @ Forward_rules.getExistientalVar (es2, ns2)
  in
  let ctx = default_pctx lems preds q_vars in
  check_staged_subsumption_aux ctx 0 True (es1, ns1) (es2, ns2)

let create_induction_hypothesis params ds1 ds2 =
  match (ds1, ds2) with
  | [s1], [s2] ->
    let ns1 = s1 |> normalise_spec in
    let s1 = ns1 |> normalisedStagedSpec2Spec in
    let used_l = used_vars ns1 in
    (* heuristic. all parameters must be used meaningfully, otherwise there's nothing to do induction on *)
    (match List.for_all (fun p -> SSet.mem p used_l) params with
    | true ->
      let s2 = s2 |> normalise_spec |> normalisedStagedSpec2Spec in
      (* quantified variables in lemma are parameters of the function *)
      let ih =
        { l_name = "IH"; l_params = params; l_left = s1; l_right = s2 }
      in
      info ~title:"induction hypothesis" "%s" (string_of_lemma ih);
      [ih]
    | false ->
      info ~title:"no induction hypothesis" "";
      [])
  | _ ->
    info ~title:"no induction hypothesis" "";
    []

(**
  Subsumption between disjunctive specs.
  S1 \/ S2 |= S3 \/ S4
*)
let check_staged_subsumption_disj :
    string ->
    string list ->
    tactic list ->
    lemma list ->
    pred_def SMap.t ->
    disj_spec ->
    disj_spec ->
    bool =
 fun mname params _ts lems preds ds1 ds2 ->
  info
    ~title:(Format.asprintf "disj subsumption: %s" mname)
    "%s\n<:\n%s" (string_of_disj_spec ds1) (string_of_disj_spec ds2);
  let lems = create_induction_hypothesis params ds1 ds2 @ lems in
  (* let ds1, ds2 = apply_tactics ts lems preds ds1 ds2 in *)
  (let@ s1 = all ~to_s:string_of_spec ds1 in
   let@ s2 = any ~name:"subsumes-disj-rhs-any" ~to_s:string_of_spec ds2 in
   check_staged_subsumption lems preds s1 s2)
  |> succeeded

let derive_predicate meth disj =
  let norm = List.map normalise_spec disj in
  (* change the last norm stage so it uses res and has an equality constraint *)
  let new_spec =
    List.map
      (fun (effs, (vs, pre, (p, h), r)) ->
        (effs, (vs, pre, (conj [p; Atomic (EQ, Var "res", r)], h), Var "res")))
      norm
    |> List.map normalisedStagedSpec2Spec
  in
  {
    p_name = meth.m_name;
    p_params = meth.m_params @ ["res"];
    p_body = new_spec;
  }
