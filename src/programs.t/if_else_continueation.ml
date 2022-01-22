effect Send : (int -> unit)
effect Done : (unit)

let send n 
(*@ requires (~Done)^* @*)
(*@ ensures Send.... Q(Send n).Q(Send n) @*)
= let a = perform Send in 
  let b = perform Send in 
  a n; b (n+1)

let server n
(*@ requires emp @*)
(*@ ensures  (Send^* ).Done @*)
= match send n with
| _ -> ()
| effect Done k -> continue k ()
| effect Send k  -> continue k 
  (fun i -> 
    if i = 0 then perform Done  
      	    else send (i-1))

let main 
(*@ requires emp @*)
(*@ ensures  (Send.Done) \/ ((Send^* ).Done)  @*)
= server (10)
 


