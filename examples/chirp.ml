(*pp camlp4o pa_macro.cmo $ARCHIMEDES_EXISTS *)
(* FFT analysis of a "chirp" signal.

   Inspired by
   http://ccrma.stanford.edu/~jos/sasp/Computational_Examples_Matlab.html

   Remark: The could could have been shortened by using Lacaml.  We
   did not however to avoid this additional dependency.
*)

open Printf
open Bigarray
module FFT = Fftw3.D

IFDEF ARCHIMEDES_EXISTS THEN
module A = Archimedes
ENDIF;;

type vec = fortran_layout FFT.Array1.complex_array

let pi = 4. *. atan 1.

(** Chirp signal
 ***********************************************************************)

type shape = Linear | Quadratic | Logarithmic

let option_default f0 = function Some f -> f | None -> f0
let pi = 4. *. atan 1.

(** [chirp ?f0 ?t1 ?f1 shape] generates a linear swept-frequency
    cosine signal function, where [f0] is the instantaneous frequency
    at time 0, and [f1] is the instantaneous frequency at time [t1].
    [f0] and [f1] are both in hertz.  If unspecified, [f0] is e-6 for
    logarithmic chirp and 0 for all other methods, [t1] is 1, and [f1]
    is 100. *)
let chirp ?f0 ?(t1=1.) ?(f1=100.) ?(phase=0.) = function
  | Linear ->
      let f0 = option_default 0. f0 in
      let a = pi *. (f1 -. f0) /. t1
      and b = 2. *. pi *. f0  in
      (fun t -> cos(a *. t *. t +. b *. t +. phase))
  | Quadratic ->
      let f0 = option_default 0. f0 in
      let a = 2. /. 3. *. pi *. (f1 -. f0) /. (t1 *. t1)
      and b = 2. *. pi *. f0 in
      (fun t -> cos(a *. t *. t *. t +. b *. t +. phase))
  | Logarithmic ->
      let f0 = option_default (exp(-. 6.)) f0 in
      let df = f1 -. f0 in
      let a = 2. *. pi *. t1 /. log df
      and b = 2. *. pi *. f0
      and x = df**(1. /. t1) in
      (fun t -> cos(a *. x**t +. b *. t +. phase))

(** Filter function (akin matlab one)
 ***********************************************************************)

let create kind n = FFT.Array1.create kind fortran_layout n

let copy0 (x:vec) (y:vec) =
  for i = 1 to Array1.dim x do y.{i} <- x.{i} done;
  for i = Array1.dim x + 1 to Array1.dim y do y.{i} <- Complex.zero done

let scal s (x:vec) =
  for i = 1 to Array1.dim x do
    let xi = x.{i} in
    x.{i} <- { Complex.re = s *. xi.Complex.re; im = s *. xi.Complex.im }
  done

(** [filter b x] returns [y] the data in vector [x] filtered with the
    FIR filter described by vector [b].  The filter implements of the
    standard difference equation:
    {v
    y(n) = b(1)*x(n) + b(2)*x(n-1) + ... + b(nb+1)*x(n-nb)
    v}
    for n = 1,..., [Array1.dim x].  *)
let filter (b:vec) (x:vec) =
  let n = Array1.dim b + Array1.dim x - 1 in
  let y = create FFT.complex n
  and b' = create FFT.complex n in
  let fftb = FFT.Array1.dft FFT.Forward y b' in
  let x' = create FFT.complex n in
  let fftx = FFT.Array1.dft FFT.Forward y x' in
  let y' = create FFT.complex n in
  let iffty = FFT.Array1.dft FFT.Backward y' y in
  copy0 b y;  FFT.exec fftb;
  copy0 x y;  FFT.exec fftx;
  for i = 1 to n do y'.{i} <- Complex.mul b'.{i} x'.{i} done;
  FFT.exec iffty;
  scal (1. /. float n) y;              (* normalize ifft *)
  Array1.sub y 1 (Array1.dim x)
;;

let () =
  let n = 10          (* number of filters = DFT length *)
  and fs = 1000.      (* sampling frequency (arbitrary) *)
  and d = 1. in       (* duration in seconds *)
  let n_graphs = 5 in (* technically =n but not space for all graphs *)

  let len = truncate(ceil(fs *. d)) + 1 in (* signal duration (samples) *)
  (* sine sweep from 0 Hz to fs/2 Hz: *)
  let ch = chirp ~t1:d ~f1:(0.5 *. fs) Linear in
  let t = create FFT.float len
  and x = create FFT.float len in
  for i = 1 to len do
    t.{i} <- float(i-1) /. fs;
    x.{i} <- ch t.{i}
  done;
  let h = create FFT.complex n in
  Array1.fill h Complex.one;            (* h = [| 1.; ...; 1. |] *)

  IFDEF ARCHIMEDES_EXISTS THEN (
    let vp0 = A.init [] ~w:1000. ~h:800. in
    let vp = A.Viewport.rows vp0 (n_graphs + 1) in
    A.Axes.box vp.(0);
    A.set_color vp.(0) A.Color.red;
    A.Vec.xy vp.(0) t x ~style:`Lines;
    let xk = create FFT.complex (Array1.dim x) in
    let y_re = create FFT.float (Array1.dim x) in
    for k = 1 to n_graphs do
      A.Axes.box vp.(k);
      (* Modulation by the complex exponential i -> exp(-I*wk*i) *)
      let wk = 2. *. pi *. float(k-1) /. float n in
      for i = 1 to Array1.dim x do
        let theta = -. wk *. float i in
        xk.{i} <- { Complex.re = x.{i} *. cos theta; im = x.{i} *. sin theta }
      done;
      (* Filter and display the real part *)
      let y = filter h xk in
      for i = 1 to Array1.dim y do y_re.{i} <- y.{i}.Complex.re done;
      A.set_color vp.(k) A.Color.blue;
      A.Vec.xy vp.(k) t y_re ~style:`Lines
    done;
    A.close vp0
  ) END
