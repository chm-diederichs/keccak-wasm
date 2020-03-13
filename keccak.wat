(module
    (func $i32.log (import "debug" "log") (param i32))
    (func $i32.log_tee (import "debug" "log_tee") (param i32) (result i32))
    ;; No i64 interop with JS yet - but maybe coming with WebAssembly BigInt
    ;; So we can instead fake this by splitting the i64 into two i32 limbs,
    ;; however these are WASM functions using i32x2.log:
    (func $i32x2.log (import "debug" "log") (param i32) (param i32))
    (func $f32.log (import "debug" "log") (param f32))
    (func $f32.log_tee (import "debug" "log_tee") (param f32) (result f32))
    (func $f64.log (import "debug" "log") (param f64))
    (func $f64.log_tee (import "debug" "log_tee") (param f64) (result f64))
    
    (memory (export "memory") 10 65536)
    
    ;; i64 logging by splitting into two i32 limbs
    (func $i64.log
        (param $0 i64)
        (call $i32x2.log
            ;; Upper limb
            (i32.wrap/i64
                (i64.shr_u (get_local $0)
                    (i64.const 32)))
            ;; Lower limb
            (i32.wrap/i64 (get_local $0))))

    (func $i64.log_tee
        (param $0 i64)
        (result i64)
        (call $i64.log (get_local $0))
        (return (get_local $0)))

  (func $init (export "init") (param $ctx i32)
      ;; schema
      ;;   i32 rate;
      ;;   i32 n_r;
      ;;   i64 length;
      ;;   i64 inlen;
      ;;   state[25, 50, 100, 200]
      )

  ;; TODO: pad properly
  (func $pad (export "pad") (param $rate i64) (param $input i32) (param $inlen i64)     

      (i64.store8 (get_local $input) (i64.const 0x80))

      (block $pad_end
          (loop $pad_start
              (i64.add (get_local $inlen) (i64.const 1))
              (i64.const 8)
              (i64.mul)
              (get_local $rate)
              (i64.rem_u)
              (i64.const 0)
              (i64.eq)
              (br_if $pad_end)

              (get_local $inlen)
              (i64.const 1)
              (i64.add)
              (set_local $inlen)

              (get_local $input)
              (i32.const 1)
              (i32.add)
              (set_local $input)

              (i64.store8 (get_local $input) (i64.const 0))
              (br $pad_start)))

      ;; CHECK -> have to ensure this byte is zeroed before input, may have written over old input
      (get_local $input)
      (i64.load (get_local $input))
      (i64.const 0x1)
      (i64.and)
      (i64.store))

  (func $absorb (export "absorb") (param $input i32) (param $inlen i32) (param $ctx i32)
      (result i32)

      (local $i i32)
      (local $width i64)
      (local $rate i32)

      (set_local $i (i32.const 0))

      (get_local $ctx)
      (i32.load)
      (tee_local $rate)
      (call $i32.log)

      (i64.load offset=8 (get_local $ctx))
      (i64.const 25)
      (i64.mul)
      (set_local $width)

      (block $input_end
          (loop $next_round
              (block $rate_end
                  (loop $input
                      ;; last permute never called
                      (i32.eq (get_local $i) (get_local $inlen))
                      (br_if $input_end)

                      (i32.mul (get_local $i) (i32.const 8))
                      (get_local $rate)
                      (i32.eq)
                      (br_if $rate_end)

                      (block $less_than_8_bytes
                          (get_local $i)
                          (get_local $inlen)
                          (i32.sub)
                          (i32.const 8)
                          (i32.lt_u)
                          (br_if $less_than_8_bytes)

                          (get_local $ctx)
                          (get_local $i)
                          (i32.add)
                          (get_local $input)
                          (get_local $i)
                          (i32.add)
                          (i64.load)
                          (i64.store offset=24)

                          ;; i++
                          (get_local $i)
                          (i32.const 8)
                          (i32.add)
                          (set_local $i)
                          (br $input))

                      ;; less than 8 bytes - load one at a time
                      (get_local $ctx)
                      (get_local $i)
                      (i32.add)
                      (get_local $input)
                      (get_local $i)
                      (i32.add)
                      (i64.load8_u)
                      (i64.store offset=24)

                      (get_local $i)
                      (i32.const 1)
                      (i32.add)
                      (br $input)))

              (block $capacity_end
                  (loop $capacity
                      (i32.mul (get_local $i) (i32.const 8))
                      (i32.wrap/i64 (get_local $width))
                      (i32.eq)
                      (br_if $capacity_end)

                      ;; filled up bitrate, add capacity zerostring
                      (get_local $ctx)
                      (get_local $i)
                      (i32.add)
                      (i64.const 0)
                      (i64.store)

                      (get_local $i)
                      (i32.const 8)
                      (i32.add)
                      (set_local $i)
                      (br $capacity)))

              (get_local $ctx)
              (call $f_permute)
              (br $next_round)))

      (i32.rem_u (get_local $i) (i32.const 8)))

  (func $squeeze (export "squeeze") (param $output i32) (param $ctx i32)
      (local $state i32)

      (local $out_0 i64)
      (local $out_1 i64)
      (local $out_2 i64)
      (local $out_3 i64)
      (local $out_4 i64)
      (local $out_5 i64)
      (local $out_6 i64)
      (local $out_7 i64)

      (get_local $ctx)
      (i32.const 24)
      (i32.add)
      (set_local $state)

      (get_local $output)
      (get_local $state)
      (i64.load)
      (i64.store)

      (call $f_permute (get_local $ctx))

      (get_local $output)
      (get_local $state)
      (i64.load)
      (i64.store offset=8)


      (call $f_permute (get_local $ctx))

      (get_local $output)
      (get_local $state)
      (i64.load)
      (i64.store offset=16)


      (call $f_permute (get_local $ctx))

      (get_local $output)
      (get_local $state)
      (i64.load)
      (i64.store offset=24)


      (call $f_permute (get_local $ctx))

      (get_local $output)
      (get_local $state)
      (i64.load)
      (i64.store offset=32)


      (call $f_permute (get_local $ctx))

      (get_local $output)
      (get_local $state)
      (i64.load)
      (i64.store offset=40)


      (call $f_permute (get_local $ctx))

      (get_local $output)
      (get_local $state)
      (i64.load)
      (i64.store offset=48)


      (call $f_permute (get_local $ctx))

      (get_local $output)
      (get_local $state)
      (i64.load)
      (i64.store offset=56))

    (func $f_permute (export "f_permute") (param $ctx i32)

        (local $c_0 i64) (local $d_0 i64)
        (local $c_1 i64) (local $d_1 i64)
        (local $c_2 i64) (local $d_2 i64)
        (local $c_3 i64) (local $d_3 i64)
        (local $c_4 i64) (local $d_4 i64)

        (local $state i32)
        (local $length i64)

        (local $count i32)
        (local $lfsr i64)
        (local $shift i64)
        (local $round_constant i64)

        (local $a_0  i64) (local $b_0  i64)
        (local $a_1  i64) (local $b_1  i64)
        (local $a_2  i64) (local $b_2  i64)
        (local $a_3  i64) (local $b_3  i64)
        (local $a_4  i64) (local $b_4  i64)
        (local $a_5  i64) (local $b_5  i64)
        (local $a_6  i64) (local $b_6  i64)
        (local $a_7  i64) (local $b_7  i64)
        (local $a_8  i64) (local $b_8  i64)
        (local $a_9  i64) (local $b_9  i64)
        (local $a_10 i64) (local $b_10 i64)
        (local $a_11 i64) (local $b_11 i64)
        (local $a_12 i64) (local $b_12 i64)
        (local $a_13 i64) (local $b_13 i64)
        (local $a_14 i64) (local $b_14 i64)
        (local $a_15 i64) (local $b_15 i64)
        (local $a_16 i64) (local $b_16 i64)
        (local $a_17 i64) (local $b_17 i64)
        (local $a_18 i64) (local $b_18 i64)
        (local $a_19 i64) (local $b_19 i64)
        (local $a_20 i64) (local $b_20 i64)
        (local $a_21 i64) (local $b_21 i64)
        (local $a_22 i64) (local $b_22 i64)
        (local $a_23 i64) (local $b_23 i64)
        (local $a_24 i64) (local $b_24 i64)

        (set_local $state (i32.add (get_local $ctx) (i32.const 24)))
        (set_local $length (i64.load offset=8 (get_local $ctx)))

        (i64.load offset=0 (get_local $state))
        (set_local $a_0)

        (i64.load offset=8 (get_local $state))
        (set_local $a_1)

        (i64.load offset=16 (get_local $state))
        (set_local $a_2)

        (i64.load offset=24 (get_local $state))
        (set_local $a_3)

        (i64.load offset=32 (get_local $state))
        (set_local $a_4)

        (i64.load offset=40 (get_local $state))
        (set_local $a_5)

        (i64.load offset=48 (get_local $state))
        (set_local $a_6)

        (i64.load offset=56 (get_local $state))
        (set_local $a_7)

        (i64.load offset=64 (get_local $state))
        (set_local $a_8)

        (i64.load offset=72 (get_local $state))
        (set_local $a_9)

        (i64.load offset=80 (get_local $state))
        (set_local $a_10)

        (i64.load offset=88 (get_local $state))
        (set_local $a_11)

        (i64.load offset=96 (get_local $state))
        (set_local $a_12)

        (i64.load offset=104 (get_local $state))
        (set_local $a_13)

        (i64.load offset=112 (get_local $state))
        (set_local $a_14)

        (i64.load offset=120 (get_local $state))
        (set_local $a_15)

        (i64.load offset=128 (get_local $state))
        (set_local $a_16)

        (i64.load offset=136 (get_local $state))
        (set_local $a_17)

        (i64.load offset=144 (get_local $state))
        (set_local $a_18)

        (i64.load offset=152 (get_local $state))
        (set_local $a_19)

        (i64.load offset=160 (get_local $state))
        (set_local $a_20)

        (i64.load offset=168 (get_local $state))
        (set_local $a_21)

        (i64.load offset=176 (get_local $state))
        (set_local $a_22)

        (i64.load offset=184 (get_local $state))
        (set_local $a_23)

        (i64.load offset=192 (get_local $state))
        (set_local $a_24)


        ;; ; ; ; ; ; ; ;;;
        ;; Perumutation ;;
        ;;; ; ; ; ; ; ; ;;

        ;; ROUND 0

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x0000000000000001)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 1

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x0000000000008082)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 2

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x800000000000808A)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 3

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x8000000080008000)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 4

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x000000000000808B)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 5

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x0000000080000001)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 6

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x8000000080008081)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 7

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x8000000000008009)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 8

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x000000000000008A)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 9

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x0000000000000088)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 10

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x0000000080008009)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 11

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x000000008000000A)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 12

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x000000008000808B)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 13

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x800000000000008B)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 14

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x8000000000008089)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 15

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x8000000000008003)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 16

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x8000000000008002)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 17

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x8000000000000080)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 18

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x000000000000800A)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 19

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x800000008000000A)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 20

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x8000000080008081)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 21

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x8000000000008080)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 22

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x0000000080000001)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))


        ;; ROUND 23

        ;; THETA

        (set_local $c_0 (get_local $a_0))
        (set_local $c_1 (get_local $a_1))
        (set_local $c_2 (get_local $a_2))
        (set_local $c_3 (get_local $a_3))
        (set_local $c_4 (get_local $a_4))

        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_5)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_10)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_15)))
        (set_local $c_0 (i64.xor (get_local $c_0) (get_local $a_20)))

        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_6)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_11)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_16)))
        (set_local $c_1 (i64.xor (get_local $c_1) (get_local $a_21)))

        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_7)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_12)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_17)))
        (set_local $c_2 (i64.xor (get_local $c_2) (get_local $a_22)))

        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_8)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_13)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_18)))
        (set_local $c_3 (i64.xor (get_local $c_3) (get_local $a_23)))

        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_9)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_14)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_19)))
        (set_local $c_4 (i64.xor (get_local $c_4) (get_local $a_24)))

        (i64.shr_u (get_local $c_1) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_1) (i64.const 1))
        (i64.or)
        (get_local $c_4)
        (i64.xor)
        (set_local $d_0)

        (set_local $a_0 (i64.xor (get_local $a_0) (get_local $d_0)))
        (set_local $a_5 (i64.xor (get_local $a_5) (get_local $d_0)))
        (set_local $a_10 (i64.xor (get_local $a_10) (get_local $d_0)))
        (set_local $a_15 (i64.xor (get_local $a_15) (get_local $d_0)))
        (set_local $a_20 (i64.xor (get_local $a_20) (get_local $d_0)))

        (i64.shr_u (get_local $c_2) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_2) (i64.const 1))
        (i64.or)
        (get_local $c_0)
        (i64.xor)
        (set_local $d_1)

        (set_local $a_1 (i64.xor (get_local $a_1) (get_local $d_1)))
        (set_local $a_6 (i64.xor (get_local $a_6) (get_local $d_1)))
        (set_local $a_11 (i64.xor (get_local $a_11) (get_local $d_1)))
        (set_local $a_16 (i64.xor (get_local $a_16) (get_local $d_1)))
        (set_local $a_21 (i64.xor (get_local $a_21) (get_local $d_1)))

        (i64.shr_u (get_local $c_3) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_3) (i64.const 1))
        (i64.or)
        (get_local $c_1)
        (i64.xor)
        (set_local $d_2)

        (set_local $a_2 (i64.xor (get_local $a_2) (get_local $d_2)))
        (set_local $a_7 (i64.xor (get_local $a_7) (get_local $d_2)))
        (set_local $a_12 (i64.xor (get_local $a_12) (get_local $d_2)))
        (set_local $a_17 (i64.xor (get_local $a_17) (get_local $d_2)))
        (set_local $a_22 (i64.xor (get_local $a_22) (get_local $d_2)))

        (i64.shr_u (get_local $c_4) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_4) (i64.const 1))
        (i64.or)
        (get_local $c_2)
        (i64.xor)
        (set_local $d_3)

        (set_local $a_3 (i64.xor (get_local $a_3) (get_local $d_3)))
        (set_local $a_8 (i64.xor (get_local $a_8) (get_local $d_3)))
        (set_local $a_13 (i64.xor (get_local $a_13) (get_local $d_3)))
        (set_local $a_18 (i64.xor (get_local $a_18) (get_local $d_3)))
        (set_local $a_23 (i64.xor (get_local $a_23) (get_local $d_3)))

        (i64.shr_u (get_local $c_0) (i64.sub (get_local $length) (i64.const 1)))
        (i64.shl (get_local $c_0) (i64.const 1))
        (i64.or)
        (get_local $c_3)
        (i64.xor)
        (set_local $d_4)

        (set_local $a_4 (i64.xor (get_local $a_4) (get_local $d_4)))
        (set_local $a_9 (i64.xor (get_local $a_9) (get_local $d_4)))
        (set_local $a_14 (i64.xor (get_local $a_14) (get_local $d_4)))
        (set_local $a_19 (i64.xor (get_local $a_19) (get_local $d_4)))
        (set_local $a_24 (i64.xor (get_local $a_24) (get_local $d_4)))

        ;; RHO & PI

        (set_local $b_0 (get_local $a_0))

        (i64.shr_u (get_local $a_1) (i64.sub (get_local $length) (i64.rem_u (i64.const 1) (get_local $length))))
        (i64.shl (get_local $a_1) (i64.rem_u (i64.const 1) (get_local $length)))
        (i64.or)
        (set_local $b_10)

        (i64.shr_u (get_local $a_10) (i64.sub (get_local $length) (i64.rem_u (i64.const 3) (get_local $length))))
        (i64.shl (get_local $a_10) (i64.rem_u (i64.const 3) (get_local $length)))
        (i64.or)
        (set_local $b_7)

        (i64.shr_u (get_local $a_7) (i64.sub (get_local $length) (i64.rem_u (i64.const 6) (get_local $length))))
        (i64.shl (get_local $a_7) (i64.rem_u (i64.const 6) (get_local $length)))
        (i64.or)
        (set_local $b_11)

        (i64.shr_u (get_local $a_11) (i64.sub (get_local $length) (i64.rem_u (i64.const 10) (get_local $length))))
        (i64.shl (get_local $a_11) (i64.rem_u (i64.const 10) (get_local $length)))
        (i64.or)
        (set_local $b_17)

        (i64.shr_u (get_local $a_17) (i64.sub (get_local $length) (i64.rem_u (i64.const 15) (get_local $length))))
        (i64.shl (get_local $a_17) (i64.rem_u (i64.const 15) (get_local $length)))
        (i64.or)
        (set_local $b_18)

        (i64.shr_u (get_local $a_18) (i64.sub (get_local $length) (i64.rem_u (i64.const 21) (get_local $length))))
        (i64.shl (get_local $a_18) (i64.rem_u (i64.const 21) (get_local $length)))
        (i64.or)
        (set_local $b_3)

        (i64.shr_u (get_local $a_3) (i64.sub (get_local $length) (i64.rem_u (i64.const 28) (get_local $length))))
        (i64.shl (get_local $a_3) (i64.rem_u (i64.const 28) (get_local $length)))
        (i64.or)
        (set_local $b_5)

        (i64.shr_u (get_local $a_5) (i64.sub (get_local $length) (i64.rem_u (i64.const 36) (get_local $length))))
        (i64.shl (get_local $a_5) (i64.rem_u (i64.const 36) (get_local $length)))
        (i64.or)
        (set_local $b_16)

        (i64.shr_u (get_local $a_16) (i64.sub (get_local $length) (i64.rem_u (i64.const 45) (get_local $length))))
        (i64.shl (get_local $a_16) (i64.rem_u (i64.const 45) (get_local $length)))
        (i64.or)
        (set_local $b_8)

        (i64.shr_u (get_local $a_8) (i64.sub (get_local $length) (i64.rem_u (i64.const 55) (get_local $length))))
        (i64.shl (get_local $a_8) (i64.rem_u (i64.const 55) (get_local $length)))
        (i64.or)
        (set_local $b_21)

        (i64.shr_u (get_local $a_21) (i64.sub (get_local $length) (i64.rem_u (i64.const 66) (get_local $length))))
        (i64.shl (get_local $a_21) (i64.rem_u (i64.const 66) (get_local $length)))
        (i64.or)
        (set_local $b_24)

        (i64.shr_u (get_local $a_24) (i64.sub (get_local $length) (i64.rem_u (i64.const 78) (get_local $length))))
        (i64.shl (get_local $a_24) (i64.rem_u (i64.const 78) (get_local $length)))
        (i64.or)
        (set_local $b_4)

        (i64.shr_u (get_local $a_4) (i64.sub (get_local $length) (i64.rem_u (i64.const 91) (get_local $length))))
        (i64.shl (get_local $a_4) (i64.rem_u (i64.const 91) (get_local $length)))
        (i64.or)
        (set_local $b_15)

        (i64.shr_u (get_local $a_15) (i64.sub (get_local $length) (i64.rem_u (i64.const 105) (get_local $length))))
        (i64.shl (get_local $a_15) (i64.rem_u (i64.const 105) (get_local $length)))
        (i64.or)
        (set_local $b_23)

        (i64.shr_u (get_local $a_23) (i64.sub (get_local $length) (i64.rem_u (i64.const 120) (get_local $length))))
        (i64.shl (get_local $a_23) (i64.rem_u (i64.const 120) (get_local $length)))
        (i64.or)
        (set_local $b_19)

        (i64.shr_u (get_local $a_19) (i64.sub (get_local $length) (i64.rem_u (i64.const 136) (get_local $length))))
        (i64.shl (get_local $a_19) (i64.rem_u (i64.const 136) (get_local $length)))
        (i64.or)
        (set_local $b_13)

        (i64.shr_u (get_local $a_13) (i64.sub (get_local $length) (i64.rem_u (i64.const 153) (get_local $length))))
        (i64.shl (get_local $a_13) (i64.rem_u (i64.const 153) (get_local $length)))
        (i64.or)
        (set_local $b_12)

        (i64.shr_u (get_local $a_12) (i64.sub (get_local $length) (i64.rem_u (i64.const 171) (get_local $length))))
        (i64.shl (get_local $a_12) (i64.rem_u (i64.const 171) (get_local $length)))
        (i64.or)
        (set_local $b_2)

        (i64.shr_u (get_local $a_2) (i64.sub (get_local $length) (i64.rem_u (i64.const 190) (get_local $length))))
        (i64.shl (get_local $a_2) (i64.rem_u (i64.const 190) (get_local $length)))
        (i64.or)
        (set_local $b_20)

        (i64.shr_u (get_local $a_20) (i64.sub (get_local $length) (i64.rem_u (i64.const 210) (get_local $length))))
        (i64.shl (get_local $a_20) (i64.rem_u (i64.const 210) (get_local $length)))
        (i64.or)
        (set_local $b_14)

        (i64.shr_u (get_local $a_14) (i64.sub (get_local $length) (i64.rem_u (i64.const 231) (get_local $length))))
        (i64.shl (get_local $a_14) (i64.rem_u (i64.const 231) (get_local $length)))
        (i64.or)
        (set_local $b_22)

        (i64.shr_u (get_local $a_22) (i64.sub (get_local $length) (i64.rem_u (i64.const 253) (get_local $length))))
        (i64.shl (get_local $a_22) (i64.rem_u (i64.const 253) (get_local $length)))
        (i64.or)
        (set_local $b_9)

        (i64.shr_u (get_local $a_9) (i64.sub (get_local $length) (i64.rem_u (i64.const 276) (get_local $length))))
        (i64.shl (get_local $a_9) (i64.rem_u (i64.const 276) (get_local $length)))
        (i64.or)
        (set_local $b_6)

        (i64.shr_u (get_local $a_6) (i64.sub (get_local $length) (i64.rem_u (i64.const 300) (get_local $length))))
        (i64.shl (get_local $a_6) (i64.rem_u (i64.const 300) (get_local $length)))
        (i64.or)
        (set_local $b_1)

        ;; CHI

        (set_local $a_0 (i64.xor (i64.and (i64.xor (get_local $b_1) (i64.const -1)) (get_local $b_2)) (get_local $b_0)))
        (set_local $a_5 (i64.xor (i64.and (i64.xor (get_local $b_6) (i64.const -1)) (get_local $b_7)) (get_local $b_5)))
        (set_local $a_10 (i64.xor (i64.and (i64.xor (get_local $b_11) (i64.const -1)) (get_local $b_12)) (get_local $b_10)))
        (set_local $a_15 (i64.xor (i64.and (i64.xor (get_local $b_16) (i64.const -1)) (get_local $b_17)) (get_local $b_15)))
        (set_local $a_20 (i64.xor (i64.and (i64.xor (get_local $b_21) (i64.const -1)) (get_local $b_22)) (get_local $b_20)))

        (set_local $a_1 (i64.xor (i64.and (i64.xor (get_local $b_2) (i64.const -1)) (get_local $b_3)) (get_local $b_1)))
        (set_local $a_6 (i64.xor (i64.and (i64.xor (get_local $b_7) (i64.const -1)) (get_local $b_8)) (get_local $b_6)))
        (set_local $a_11 (i64.xor (i64.and (i64.xor (get_local $b_12) (i64.const -1)) (get_local $b_13)) (get_local $b_11)))
        (set_local $a_16 (i64.xor (i64.and (i64.xor (get_local $b_17) (i64.const -1)) (get_local $b_18)) (get_local $b_16)))
        (set_local $a_21 (i64.xor (i64.and (i64.xor (get_local $b_22) (i64.const -1)) (get_local $b_23)) (get_local $b_21)))

        (set_local $a_2 (i64.xor (i64.and (i64.xor (get_local $b_3) (i64.const -1)) (get_local $b_4)) (get_local $b_2)))
        (set_local $a_7 (i64.xor (i64.and (i64.xor (get_local $b_8) (i64.const -1)) (get_local $b_9)) (get_local $b_7)))
        (set_local $a_12 (i64.xor (i64.and (i64.xor (get_local $b_13) (i64.const -1)) (get_local $b_14)) (get_local $b_12)))
        (set_local $a_17 (i64.xor (i64.and (i64.xor (get_local $b_18) (i64.const -1)) (get_local $b_19)) (get_local $b_17)))
        (set_local $a_22 (i64.xor (i64.and (i64.xor (get_local $b_23) (i64.const -1)) (get_local $b_24)) (get_local $b_22)))

        (set_local $a_3 (i64.xor (i64.and (i64.xor (get_local $b_4) (i64.const -1)) (get_local $b_0)) (get_local $b_3)))
        (set_local $a_8 (i64.xor (i64.and (i64.xor (get_local $b_9) (i64.const -1)) (get_local $b_5)) (get_local $b_8)))
        (set_local $a_13 (i64.xor (i64.and (i64.xor (get_local $b_14) (i64.const -1)) (get_local $b_10)) (get_local $b_13)))
        (set_local $a_18 (i64.xor (i64.and (i64.xor (get_local $b_19) (i64.const -1)) (get_local $b_15)) (get_local $b_18)))
        (set_local $a_23 (i64.xor (i64.and (i64.xor (get_local $b_24) (i64.const -1)) (get_local $b_20)) (get_local $b_23)))

        (set_local $a_4 (i64.xor (i64.and (i64.xor (get_local $b_0) (i64.const -1)) (get_local $b_1)) (get_local $b_4)))
        (set_local $a_9 (i64.xor (i64.and (i64.xor (get_local $b_5) (i64.const -1)) (get_local $b_6)) (get_local $b_9)))
        (set_local $a_14 (i64.xor (i64.and (i64.xor (get_local $b_10) (i64.const -1)) (get_local $b_11)) (get_local $b_14)))
        (set_local $a_19 (i64.xor (i64.and (i64.xor (get_local $b_15) (i64.const -1)) (get_local $b_16)) (get_local $b_19)))
        (set_local $a_24 (i64.xor (i64.and (i64.xor (get_local $b_20) (i64.const -1)) (get_local $b_21)) (get_local $b_24)))

        ;; IOTA

        (get_local $a_0)
        (i64.const 0x8000000080008008)
        (i64.xor)
        (set_local $a_0)

        (call $i64.log (get_local $a_0))
        (call $i32.log (i32.const 0))

        ;; PERMUTATION END

        (get_local $state)
        (get_local $a_0)
        (i64.store offset=0)

        (get_local $state)
        (get_local $a_1)
        (i64.store offset=8)

        (get_local $state)
        (get_local $a_2)
        (i64.store offset=16)

        (get_local $state)
        (get_local $a_3)
        (i64.store offset=24)

        (get_local $state)
        (get_local $a_4)
        (i64.store offset=32)

        (get_local $state)
        (get_local $a_5)
        (i64.store offset=40)

        (get_local $state)
        (get_local $a_6)
        (i64.store offset=48)

        (get_local $state)
        (get_local $a_7)
        (i64.store offset=56)

        (get_local $state)
        (get_local $a_8)
        (i64.store offset=64)

        (get_local $state)
        (get_local $a_9)
        (i64.store offset=72)

        (get_local $state)
        (get_local $a_10)
        (i64.store offset=80)

        (get_local $state)
        (get_local $a_11)
        (i64.store offset=88)

        (get_local $state)
        (get_local $a_12)
        (i64.store offset=96)

        (get_local $state)
        (get_local $a_13)
        (i64.store offset=104)

        (get_local $state)
        (get_local $a_14)
        (i64.store offset=112)

        (get_local $state)
        (get_local $a_15)
        (i64.store offset=120)

        (get_local $state)
        (get_local $a_16)
        (i64.store offset=128)

        (get_local $state)
        (get_local $a_17)
        (i64.store offset=136)

        (get_local $state)
        (get_local $a_18)
        (i64.store offset=144)

        (get_local $state)
        (get_local $a_19)
        (i64.store offset=152)

        (get_local $state)
        (get_local $a_20)
        (i64.store offset=160)

        (get_local $state)
        (get_local $a_21)
        (i64.store offset=168)

        (get_local $state)
        (get_local $a_22)
        (i64.store offset=176)

        (get_local $state)
        (get_local $a_23)
        (i64.store offset=184)

        (get_local $state)
        (get_local $a_24)
        (i64.store offset=192)))
