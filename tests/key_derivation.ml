let cs =
  let module M = struct
    type t = Cstruct.t
    let pp = Cstruct.hexdump_pp
    let equal = Cstruct.equal
  end in (module M : Alcotest.TESTABLE with type t = M.t)

let secret0 = Cstruct.of_hex {|
33 ad 0a 1c 60 7e c0 3b  09 e6 cd 98 93 68 0c e2
10 ad f3 00 aa 1f 26 60  e1 b2 2e 10 f1 70 f9 2a
|}

let extract_secret_early () =
  (* draft-ietf-tls-tls13-vectors-07 Sec 3*)
  let salt = Cstruct.empty
  and ikm = Cstruct.create 32
  in
  Alcotest.check cs __LOC__ secret0 (Hkdf.extract ~hash:`SHA256 ~salt ikm)

let expand0 = Cstruct.of_hex {|
6f 26 15 a1 08 c7 02 c5  67 8f 54 fc 9d ba b6 97
16 c0 76 18 9c 48 25 0c  eb ea c3 57 6c 36 11 ba
|}

let derive_hs_secret () =
  let hash = Nocrypto.Hash.digest `SHA256 Cstruct.empty in
  Alcotest.check cs __LOC__ expand0
    (Handshake_crypto13.expand_label `SHA256 secret0 "derived" hash 32)

let hs_secret = Cstruct.of_hex {|
1d c8 26 e9 36 06 aa 6f  dc 0a ad c1 2f 74 1b 01
04 6a a6 b9 9f 69 1e d2  21 a9 f0 ca 04 3f be ac
|}

(* TODO: ikm should be computed (ECDHE) from the key share in client hello (see
   below), and the private key written in the RFC. *)
let ikm = Cstruct.of_hex {|
8b d4 05 4f b5 5b 9d 63  fd fb ac f9 f0 4b 9f 0d
35 e6 d6 3f 53 75 63 ef  d4 62 72 90 0f 89 49 2d
|}

let extract_handshake () =
  Alcotest.check cs __LOC__ hs_secret
    (Hkdf.extract ~hash:`SHA256 ~salt:expand0 ikm)

let ch = Cstruct.of_hex {|
01 00 00 c0 03 03 cb 34  ec b1 e7 81 63 ba 1c 38
c6 da cb 19 6a 6d ff a2  1a 8d 99 12 ec 18 a2 ef
62 83 02 4d ec e7 00 00  06 13 01 13 03 13 02 01
00 00 91 00 00 00 0b 00  09 00 00 06 73 65 72 76
65 72 ff 01 00 01 00 00  0a 00 14 00 12 00 1d 00
17 00 18 00 19 01 00 01  01 01 02 01 03 01 04 00
23 00 00 00 33 00 26 00  24 00 1d 00 20 99 38 1d
e5 60 e4 bd 43 d2 3d 8e  43 5a 7d ba fe b3 c0 6e
51 c1 3c ae 4d 54 13 69  1e 52 9a af 2c 00 2b 00
03 02 03 04 00 0d 00 20  00 1e 04 03 05 03 06 03
02 03 08 04 08 05 08 06  04 01 05 01 06 01 02 01
04 02 05 02 06 02 02 02  00 2d 00 02 01 01 00 1c
00 02 40 01
|}

let sh = Cstruct.of_hex {|
02 00 00 56 03 03 a6 af  06 a4 12 18 60 dc 5e 6e
60 24 9c d3 4c 95 93 0c  8a c5 cb 14 34 da c1 55
77 2e d3 e2 69 28 00 13  01 00 00 2e 00 33 00 24
00 1d 00 20 c9 82 88 76  11 20 95 fe 66 76 2b db
f7 c6 72 e1 56 d6 cc 25  3b 83 3d f1 dd 69 b1 b0
4e 75 1f 0f 00 2b 00 02  03 04
|}

let c_hs_traffic_secret = Cstruct.of_hex {|
b3 ed db 12 6e 06 7f 35  a7 80 b3 ab f4 5e 2d 8f
3b 1a 95 07 38 f5 2e 96  00 74 6a 0e 27 a5 5a 21
|}

let s_hs_traffic_secret = Cstruct.of_hex {|
b6 7b 7d 69 0c c1 6c 4e  75 e5 42 13 cb 2d 37 b4
e9 c9 12 bc de d9 10 5d  42 be fd 59 d3 91 ad 38
|}

let derive_c_hs_traffic () =
  let hash = Nocrypto.Hash.digest `SHA256 (Cstruct.append ch sh) in
  Alcotest.check cs __LOC__ c_hs_traffic_secret
    (Handshake_crypto13.expand_label `SHA256 hs_secret "c hs traffic" hash 32)

let derive_s_hs_traffic () =
  let hash = Nocrypto.Hash.digest `SHA256 (Cstruct.append ch sh) in
  Alcotest.check cs __LOC__ s_hs_traffic_secret
    (Handshake_crypto13.expand_label `SHA256 hs_secret "s hs traffic" hash 32)

let master = Cstruct.of_hex {|
43 de 77 e0 c7 77 13 85  9a 94 4d b9 db 25 90 b5
31 90 a6 5b 3e e2 e4 f1  2d d7 a0 bb 7c e2 54 b4
|}

let derive_master () =
  let hash = Nocrypto.Hash.digest `SHA256 Cstruct.empty in
  Alcotest.check cs __LOC__ master
    (Handshake_crypto13.expand_label `SHA256 hs_secret "derived" hash 32)

let master_secret = Cstruct.of_hex {|
18 df 06 84 3d 13 a0 8b  f2 a4 49 84 4c 5f 8a 47
80 01 bc 4d 4c 62 79 84  d5 a4 1d a8 d0 40 29 19
|}

let extract_master () =
  Alcotest.check cs __LOC__ master_secret
    (Hkdf.extract ~hash:`SHA256 ~salt:master (Cstruct.create 32))

let write_handshake_key = Cstruct.of_hex {|
3f ce 51 60 09 c2 17 27  d0 f2 e4 e8 6e e4 03 bc
|}

let write_handshake_iv = Cstruct.of_hex {|
5d 31 3e b2 67 12 76 ee  13 00 0b 30
|}

let derive_handshake_keys () =
  Alcotest.check cs __LOC__ write_handshake_key
    (Handshake_crypto13.expand_label `SHA256 s_hs_traffic_secret "key" Cstruct.empty 16) ;
  Alcotest.check cs __LOC__ write_handshake_iv
    (Handshake_crypto13.expand_label `SHA256 s_hs_traffic_secret "iv" Cstruct.empty 12)

let finished_expanded = Cstruct.of_hex {|
00 8d 3b 66 f8 16 ea 55  9f 96 b5 37 e8 85 c3 1f
c0 68 bf 49 2c 65 2f 01  f2 88 a1 d8 cd c1 9f c8
|}

let finished_key = Cstruct.of_hex {|
9b 9b 14 1d 90 63 37 fb  d2 cb dc e7 1d f4 de da
4a b4 2c 30 95 72 cb 7f  ff ee 54 54 b7 8f 07 18
|}

let enc_ext = Cstruct.of_hex {|
08 00 00 24 00 22 00 0a  00 14 00 12 00 1d 00 17
00 18 00 19 01 00 01 01  01 02 01 03 01 04 00 1c
00 02 40 01 00 00 00 00
|}

let cert = Cstruct.of_hex {|
0b 00 01 b9 00 00 01 b5  00 01 b0 30 82 01 ac 30
82 01 15 a0 03 02 01 02  02 01 02 30 0d 06 09 2a
86 48 86 f7 0d 01 01 0b  05 00 30 0e 31 0c 30 0a
06 03 55 04 03 13 03 72  73 61 30 1e 17 0d 31 36
30 37 33 30 30 31 32 33  35 39 5a 17 0d 32 36 30
37 33 30 30 31 32 33 35  39 5a 30 0e 31 0c 30 0a
06 03 55 04 03 13 03 72  73 61 30 81 9f 30 0d 06
09 2a 86 48 86 f7 0d 01  01 01 05 00 03 81 8d 00
30 81 89 02 81 81 00 b4  bb 49 8f 82 79 30 3d 98
08 36 39 9b 36 c6 98 8c  0c 68 de 55 e1 bd b8 26
d3 90 1a 24 61 ea fd 2d  e4 9a 91 d0 15 ab bc 9a
95 13 7a ce 6c 1a f1 9e  aa 6a f9 8c 7c ed 43 12
09 98 e1 87 a8 0e e0 cc  b0 52 4b 1b 01 8c 3e 0b
63 26 4d 44 9a 6d 38 e2  2a 5f da 43 08 46 74 80
30 53 0e f0 46 1c 8c a9  d9 ef bf ae 8e a6 d1 d0
3e 2b d1 93 ef f0 ab 9a  80 02 c4 74 28 a6 d3 5a
8d 88 d7 9f 7f 1e 3f 02  03 01 00 01 a3 1a 30 18
30 09 06 03 55 1d 13 04  02 30 00 30 0b 06 03 55
1d 0f 04 04 03 02 05 a0  30 0d 06 09 2a 86 48 86
f7 0d 01 01 0b 05 00 03  81 81 00 85 aa d2 a0 e5
b9 27 6b 90 8c 65 f7 3a  72 67 17 06 18 a5 4c 5f
8a 7b 33 7d 2d f7 a5 94  36 54 17 f2 ea e8 f8 a5
8c 8f 81 72 f9 31 9c f3  6b 7f d6 c5 5b 80 f2 1a
03 01 51 56 72 60 96 fd  33 5e 5e 67 f2 db f1 02
70 2e 60 8c ca e6 be c1  fc 63 a4 2a 99 be 5c 3e
b7 10 7c 3c 54 e9 b9 eb  2b d5 20 3b 1c 3b 84 e0
a8 b2 f7 59 40 9b a3 ea  c9 d9 1d 40 2d cc 0c c8
f8 96 12 29 ac 91 87 b4  2b 4d e1 00 00
|}

let cert_verify = Cstruct.of_hex {|
0f 00 00 84 08 04 00 80  5a 74 7c 5d 88 fa 9b d2
e5 5a b0 85 a6 10 15 b7  21 1f 82 4c d4 84 14 5a
b3 ff 52 f1 fd a8 47 7b  0b 7a bc 90 db 78 e2 d3
3a 5c 14 1a 07 86 53 fa  6b ef 78 0c 5e a2 48 ee
aa a7 85 c4 f3 94 ca b6  d3 0b be 8d 48 59 ee 51
1f 60 29 57 b1 54 11 ac  02 76 71 45 9e 46 44 5c
9e a5 8c 18 1e 81 8e 95  b8 c3 fb 0b f3 27 84 09
d3 be 15 2a 3d a5 04 3e  06 3d da 65 cd f5 ae a2
0d 53 df ac d4 2f 74 f3
|}

let derive_finished () =
  Alcotest.check cs __LOC__ finished_expanded
    (Handshake_crypto13.expand_label `SHA256 s_hs_traffic_secret "finished" Cstruct.empty 32) ;
  let hash = Nocrypto.Hash.digest `SHA256 (Cstruct.concat [ ch ; sh ; enc_ext ; cert ; cert_verify ]) in
  Alcotest.check cs __LOC__ finished_key
    (Nocrypto.Hash.mac `SHA256 ~key:finished_expanded hash)

let finished = Cstruct.of_hex {|
14 00 00 20 9b 9b 14 1d  90 63 37 fb d2 cb dc e7
1d f4 de da 4a b4 2c 30  95 72 cb 7f ff ee 54 54
b7 8f 07 18
|}

let c_ap_traffic = Cstruct.of_hex {|
9e 40 64 6c e7 9a 7f 9d  c0 5a f8 88 9b ce 65 52
87 5a fa 0b 06 df 00 87  f7 92 eb b7 c1 75 04 a5
|}

let s_ap_traffic = Cstruct.of_hex {|
a1 1a f9 f0 55 31 f8 56  ad 47 11 6b 45 a9 50 32
82 04 b4 f4 4b fb 6b 3a  4b 4f 1f 3f cb 63 16 43
|}

let exp_master = Cstruct.of_hex {|
fe 22 f8 81 17 6e da 18  eb 8f 44 52 9e 67 92 c5
0c 9a 3f 89 45 2f 68 d8  ae 31 1b 43 09 d3 cf 50
|}

let derive_traffic_keys () =
  let hash = Nocrypto.Hash.digest `SHA256 (Cstruct.concat [ ch ; sh ; enc_ext ; cert ; cert_verify ; finished ]) in
  Alcotest.check cs __LOC__ c_ap_traffic
    (Handshake_crypto13.expand_label `SHA256 master_secret "c ap traffic" hash 32) ;
  Alcotest.check cs __LOC__ s_ap_traffic
    (Handshake_crypto13.expand_label `SHA256 master_secret "s ap traffic" hash 32) ;
  Alcotest.check cs __LOC__ exp_master
    (Handshake_crypto13.expand_label `SHA256 master_secret "exp master" hash 32)

let app_write_key = Cstruct.of_hex {|
9f 02 28 3b 6c 9c 07 ef  c2 6b b9 f2 ac 92 e3 56
|}

let app_write_iv = Cstruct.of_hex {|
cf 78 2b 88 dd 83 54 9a  ad f1 e9 84
|}

let appdata_write () =
  Alcotest.check cs __LOC__ app_write_key
    (Handshake_crypto13.expand_label `SHA256 s_ap_traffic "key" Cstruct.empty 16) ;
  Alcotest.check cs __LOC__ app_write_iv
    (Handshake_crypto13.expand_label `SHA256 s_ap_traffic "iv" Cstruct.empty 12)

let app_read_key = Cstruct.of_hex {|
17 42 2d da 59 6e d5 d9  ac d8 90 e3 c6 3f 50 51
|}

let app_read_iv = Cstruct.of_hex {|
5b 78 92 3d ee 08 57 90  33 e5 23 d9
|}

let appdata_read () =
  Alcotest.check cs __LOC__ app_read_key
    (Handshake_crypto13.expand_label `SHA256 c_ap_traffic "key" Cstruct.empty 16) ;
  Alcotest.check cs __LOC__ app_read_iv
    (Handshake_crypto13.expand_label `SHA256 c_ap_traffic "iv" Cstruct.empty 12)

let hs_read_key = Cstruct.of_hex {|
db fa a6 93 d1 76 2c 5b  66 6a f5 d9 50 25 8d 01
|}

let hs_read_iv = Cstruct.of_hex {|
5b d3 c7 1b 83 6e 0b 76  bb 73 26 5f
|}

let hs_read () =
  Alcotest.check cs __LOC__ hs_read_key
    (Handshake_crypto13.expand_label `SHA256 c_hs_traffic_secret "key" Cstruct.empty 16) ;
  Alcotest.check cs __LOC__ hs_read_iv
    (Handshake_crypto13.expand_label `SHA256 c_hs_traffic_secret "iv" Cstruct.empty 12)

let c_finished = Cstruct.of_hex {|
14 00 00 20 a8 ec 43 6d  67 76 34 ae 52 5a c1 fc
eb e1 1a 03 9e c1 76 94  fa c6 e9 85 27 b6 42 f2
ed d5 ce 61
|}


let res_master = Cstruct.of_hex {|
7d f2 35 f2 03 1d 2a 05  12 87 d0 2b 02 41 b0 bf
da f8 6c c8 56 23 1f 2d  5a ba 46 c4 34 ec 19 6c
|}

let resumption () =
  let hash = Nocrypto.Hash.digest `SHA256 (Cstruct.concat [ ch ; sh ; enc_ext ; cert ; cert_verify ; finished ; c_finished ]) in
  Alcotest.check cs __LOC__ res_master
    (Handshake_crypto13.expand_label `SHA256 master_secret "res master" hash 32)

let tests = [
  "initial extract", `Quick, extract_secret_early ;
  "initial derive", `Quick, derive_hs_secret ;
  "handshake extract", `Quick, extract_handshake ;
  "derive c hs", `Quick, derive_c_hs_traffic ;
  "derive s hs", `Quick, derive_s_hs_traffic ;
  "derive master", `Quick, derive_master ;
  "extract master", `Quick, extract_master ;
  "derive hanshake keys", `Quick, derive_handshake_keys ;
  "derive finished", `Quick, derive_finished ;
  "derive traffic keys", `Quick, derive_traffic_keys ;
  "application write keys", `Quick, appdata_write ;
  "application read keys", `Quick, appdata_read ;
  "hs read keys", `Quick, hs_read ;
  "resumption key", `Quick, resumption ;
]

let () = Alcotest.run "Key derivation tests"
    [ "key extraction and derivation", tests ]