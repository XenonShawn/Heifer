effect E: unit 

let two_locations () 
(*@ ex z1 z2 ret;
   E(i->0*j->0, ret);
   req i->z1 * y->z2 ; 
   Norm(i->z1+1*j->z2+2, ret)
@*)
= let i = ref 0 in 
  let j = ref 0 in 
  let ret = perform (E) in 
  i := !i + 1;
  j := !j + 1;
  ret