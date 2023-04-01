effect Read : int 
effect Write : int -> unit 

(* let (i: int ref) = Sys.opaque_identity (ref 0) *)

let read () 
(*@ 
   ex ret; 
   Read(emp, ret);
   Norm(emp, ret)
@*)
= perform Read

let write n 
(*@ 
   ex ret; 
   Write(emp, n,  ret);
   Norm(emp, ret)
@*)
= perform (Write n)

let test ()
(*@ 
  ex x1; 
  Read(emp, x1); 
  ex x2; 
  Write(emp, (x1+1), x2); 
  ex x3; 
  Read(emp, x3); 
  Norm(emp, x3)
@*)
= 
  let x = read () in 
  let y = x +1 in 
  write y;
  read () 

let write_handler i  
(*@ 
  ex x1 ret z; 
  Read(emp, x1); 
  req i-> z; 
  Read(i->x1+1,  ret);
  Norm(emp, ret)
@*)
= 
  match test () with
  | v -> v
  | effect (Write x) k -> i := x; (continue k ())


let read_handler  ()
(*@ 
  ex i; 
  Norm(i->2,  10)
@*)
=
  let i = Sys.opaque_identity (ref 0) in 
  match write_handler i with
  | v -> v 
  | effect Read k -> (continue k (!i))


