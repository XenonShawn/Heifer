(* Prints the number of solutions to a given n-Queens problem.

   Adapted from
     https://github.com/effect-handlers/effect-handlers-bench/blob/ca4ed12fc2265c16c562016ec09f0466d81d1ddd/benchmarks/ocaml/001_nqueens/001_nqueens_ocaml.ml

  回溯法进行求解八皇后问题
*)

open Effect.Deep
open Multicont.Deep 

type _ Effect.t += Pick : int -> int Effect.t
exception Fail

let n = try int_of_string Sys.argv.(1) with _ -> 8

(* n-Queens logic. *)
let rec safe queen diag xs =
  match xs with
  | [] -> true
  | q :: qs -> queen <> q && queen <> q + diag && queen <> q - diag &&
               safe queen (diag + 1) qs

let rec find_solution n col : int list =
  if col = 0 then []
  else let sol = find_solution n (col - 1) in
       let queen = Effect.perform (Pick n) in
       if safe queen 1 sol then queen::sol else raise Fail

let find_solution_1 (): int list =
  let sol = [] in
  let queen = Effect.perform (Pick 4) in
  if safe queen 1 sol then queen::sol else raise Fail

let find_solution_2 () : int list =
  let sol = find_solution_1 ()  in
  let queen = Effect.perform (Pick 4) in
  if safe queen 1 sol then queen::sol else raise Fail

let find_solution_3 () : int list =
  let sol = find_solution_2 () in
  let queen = Effect.perform (Pick 4) in
  if safe queen 1 sol then queen::sol else raise Fail

let find_solution_4 (): int list =
  let sol = find_solution_3 () in
  let queen = Effect.perform (Pick 4) in
  if safe queen 1 sol then queen::sol else raise Fail

(* Deep effect handler that counts the number of solutions to an
   n-Queens problem. *)
let count_queens_solutions =
  { retc = (fun _ -> 1) (* If the computation returns, then we have found a solution. *)
  ; exnc = (fun e -> match e with Fail -> 0 | _ -> raise e) (* If the computation fails, then we have not found a solution. *)
  ; effc = (fun (type a) (eff : a Effect.t) ->
    match eff with
    | Pick n -> (* We handle [Pick] by successively trying to place
                   Queens on the board by invoking the provided
                   continuation with different values. Each invocation
                   returns the number of solutions in the
                   subcomputation. *)
       Some (fun (k : (a, _) continuation) ->
           (* Convert [k] into a multi-shot resumption *)
           let r = promote k in
           let rec loop i acc =
             if i > n then acc
             else (* Invoke the resumption. This branch may be
                     executed many times. *)
                  let nsol = resume r i in
                  loop (i + 1) (nsol + acc)
           in
           loop 1 0)
    | _ -> None) }

let queens_count n =
  match_with (fun () -> find_solution n n) () count_queens_solutions

let queens_count_4 () = 
  match_with (fun () -> find_solution_4 ()) () count_queens_solutions
  
let _ =
  Printf.printf "queens_count_n: %d\n" (queens_count n);
  Printf.printf "queens_count_4: %d\n" (queens_count_4 ())

  
