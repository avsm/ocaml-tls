open OUnit2
open Tls


let cs_appends = function
  | []   -> Cstruct.create 0
  | [cs] -> cs
  | csn  ->
      let cs = Cstruct.(create @@ lenv csn) in
      let _ =
        List.fold_left
          (fun off e ->
            let len = Cstruct.len e in
            ( Cstruct.blit e 0 cs off len ; off + len ))
          0 csn in
      cs

let (<>) cs1 cs2 = cs_appends [ cs1; cs2 ]

let list_to_cstruct xs =
  let open Cstruct in
  let l = List.length xs in
  let buf = create l in
  for i = 0 to pred l do
    set_uint8 buf i (List.nth xs i)
  done;
  buf

let uint16_to_cstruct i =
  let open Cstruct in
  let buf = create 2 in
  BE.set_uint16 buf 0 i;
  buf

let good_version_parser major minor result _ =
  let ver = list_to_cstruct [ major ; minor ] in
  Reader.(match parse_version ver with
          | Or_error.Ok v    -> assert_equal v result
          | Or_error.Error _ -> assert_failure "Version parser broken")

let bad_version_parser major minor _ =
  let ver = list_to_cstruct [ major ; minor ] in
  Reader.(match parse_version ver with
          | Or_error.Ok v    -> assert_failure "Version parser broken"
          | Or_error.Error _ -> assert_bool "unknown version" true)

let parse_version_too_short _ =
  let ver = list_to_cstruct [ 0 ] in
  Reader.(match parse_version ver with
          | Or_error.Ok v    -> assert_failure "Version parser broken"
          | Or_error.Error _ -> assert_bool "length too short" true)

let version_parser_tests = [
  good_version_parser 3 0 Core.SSL_3 ;
  good_version_parser 3 1 Core.TLS_1_0 ;
  good_version_parser 3 2 Core.TLS_1_1 ;
  good_version_parser 3 3 Core.TLS_1_2 ;
  good_version_parser 3 4 Core.TLS_1_X ;
  good_version_parser 3 42 Core.TLS_1_X ;

  bad_version_parser 2 4 ;
  bad_version_parser 4 4 ;
  bad_version_parser 0 2 ;

  parse_version_too_short
]

let version_tests =
  List.mapi
    (fun i f -> "Parse version " ^ string_of_int i >:: f)
    version_parser_tests

let good_header_parser (ct, (major, minor), l, (resct, resv)) _ =
  let buf =
    let pre = list_to_cstruct [ ct ; major ; minor ] in
    pre <> uint16_to_cstruct l
  in
  match Reader.parse_hdr buf with
  | (Some c, Some v, l') -> assert_equal c resct ;
                            assert_equal v resv ;
                            assert_equal l' l
  | _                    -> assert_failure "header parser broken"

let good_headers = [
  ( 20 , (3, 1), 100,  ( Packet.CHANGE_CIPHER_SPEC , Core.TLS_1_0) ) ;
  ( 21 , (3, 2), 10,   ( Packet.ALERT , Core.TLS_1_1) ) ;
  ( 22 , (3, 3), 1000, ( Packet.HANDSHAKE , Core.TLS_1_2) ) ;
  ( 23 , (3, 0), 1,    ( Packet.APPLICATION_DATA , Core.SSL_3) ) ;
  ( 24 , (3, 4), 20,   ( Packet.HEARTBEAT , Core.TLS_1_X) ) ;
]

let good_headers_tests =
  List.mapi
    (fun i args -> "Good header " ^ string_of_int i >:: good_header_parser args)
    good_headers

let bad_header_parser (ct, (major, minor), l) _ =
  let buf =
    let pre = list_to_cstruct [ ct ; major ; minor ] in
    pre <> uint16_to_cstruct l
  in
  match Reader.parse_hdr buf with
  | (Some c, Some v, l') -> assert_failure "header parser broken"
  | _                    -> assert_bool "header parser good" true

let bad_headers = [
  ( 19 , (3, 1), 100 ) ;
  ( 20 , (5, 1), 100 ) ;
  ( 16 , (3, 1), 100 ) ;
  ( 30 , (3, 1), 100 ) ;
  ( 20 , (0, 1), 100 ) ;
  ( 25 , (3, 3), 100 ) ;
]

let bad_headers_tests =
  List.mapi
    (fun i args -> "Bad header " ^ string_of_int i >:: bad_header_parser args)
    bad_headers

let good_alert_parser (lvl, typ, expected) _ =
  let buf = list_to_cstruct [ lvl ; typ ] in
  Reader.(match parse_alert buf with
          | Or_error.Ok al   -> assert_equal al expected
          | Or_error.Error _ -> assert_failure "alert parser broken")

let good_alerts =
  let w = Packet.WARNING in
  let f = Packet.FATAL in
  [
    (1, 0, (w, Packet.CLOSE_NOTIFY));
    (2, 0, (f, Packet.CLOSE_NOTIFY));
    (1, 10, (w, Packet.UNEXPECTED_MESSAGE));
    (2, 10, (f, Packet.UNEXPECTED_MESSAGE));
    (1, 20, (w, Packet.BAD_RECORD_MAC));
    (2, 20, (f, Packet.BAD_RECORD_MAC));
    (1, 21, (w, Packet.DECRYPTION_FAILED));
    (2, 21, (f, Packet.DECRYPTION_FAILED));
    (1, 22, (w, Packet.RECORD_OVERFLOW));
    (2, 22, (f, Packet.RECORD_OVERFLOW));
    (1, 30, (w, Packet.DECOMPRESSION_FAILURE));
    (2, 30, (f, Packet.DECOMPRESSION_FAILURE));
    (1, 40, (w, Packet.HANDSHAKE_FAILURE));
    (2, 40, (f, Packet.HANDSHAKE_FAILURE));
    (1, 41, (w, Packet.NO_CERTIFICATE_RESERVED));
    (2, 41, (f, Packet.NO_CERTIFICATE_RESERVED));
    (1, 42, (w, Packet.BAD_CERTIFICATE));
    (2, 42, (f, Packet.BAD_CERTIFICATE));
    (1, 43, (w, Packet.UNSUPPORTED_CERTIFICATE));
    (2, 43, (f, Packet.UNSUPPORTED_CERTIFICATE));
    (1, 44, (w, Packet.CERTIFICATE_REVOKED));
    (2, 44, (f, Packet.CERTIFICATE_REVOKED));
    (1, 45, (w, Packet.CERTIFICATE_EXPIRED));
    (2, 45, (f, Packet.CERTIFICATE_EXPIRED));
    (1, 46, (w, Packet.CERTIFICATE_UNKNOWN));
    (2, 46, (f, Packet.CERTIFICATE_UNKNOWN));
    (1, 47, (w, Packet.ILLEGAL_PARAMETER));
    (2, 47, (f, Packet.ILLEGAL_PARAMETER));
    (1, 48, (w, Packet.UNKNOWN_CA));
    (2, 48, (f, Packet.UNKNOWN_CA));
    (1, 49, (w, Packet.ACCESS_DENIED));
    (2, 49, (f, Packet.ACCESS_DENIED));
    (1, 50, (w, Packet.DECODE_ERROR));
    (2, 50, (f, Packet.DECODE_ERROR));
    (1, 51, (w, Packet.DECRYPT_ERROR));
    (2, 51, (f, Packet.DECRYPT_ERROR));
    (1, 60, (w, Packet.EXPORT_RESTRICTION_RESERVED));
    (2, 60, (f, Packet.EXPORT_RESTRICTION_RESERVED));
    (1, 70, (w, Packet.PROTOCOL_VERSION));
    (2, 70, (f, Packet.PROTOCOL_VERSION));
    (1, 71, (w, Packet.INSUFFICIENT_SECURITY));
    (2, 71, (f, Packet.INSUFFICIENT_SECURITY));
    (1, 80, (w, Packet.INTERNAL_ERROR));
    (2, 80, (f, Packet.INTERNAL_ERROR));
    (1, 90, (w, Packet.USER_CANCELED));
    (2, 90, (f, Packet.USER_CANCELED));
    (1, 100, (w, Packet.NO_RENEGOTIATION));
    (2, 100, (f, Packet.NO_RENEGOTIATION));
    (1, 110, (w, Packet.UNSUPPORTED_EXTENSION));
    (2, 110, (f, Packet.UNSUPPORTED_EXTENSION));
    (1, 111, (w, Packet.CERTIFICATE_UNOBTAINABLE));
    (2, 111, (f, Packet.CERTIFICATE_UNOBTAINABLE));
    (1, 112, (w, Packet.UNRECOGNIZED_NAME));
    (2, 112, (f, Packet.UNRECOGNIZED_NAME));
    (1, 113, (w, Packet.BAD_CERTIFICATE_STATUS_RESPONSE));
    (2, 113, (f, Packet.BAD_CERTIFICATE_STATUS_RESPONSE));
    (1, 114, (w, Packet.BAD_CERTIFICATE_HASH_VALUE));
    (2, 114, (f, Packet.BAD_CERTIFICATE_HASH_VALUE));
    (1, 115, (w, Packet.UNKNOWN_PSK_IDENTITY));
    (2, 115, (f, Packet.UNKNOWN_PSK_IDENTITY));
  ]

let good_alert_tests =
  List.mapi
    (fun i args -> "Good alert " ^ string_of_int i >:: good_alert_parser args)
    good_alerts

let bad_alert_parser (lvl, typ) _ =
  let buf = list_to_cstruct [ lvl ; typ ] in
  Reader.(match parse_alert buf with
          | Or_error.Ok _    -> assert_failure "bad alert passes"
          | Or_error.Error _ -> assert_bool "bad alert fails" true)

let bad_alerts = [ (3, 0); (1, 1); (2, 200); (0, 200) ]

let alert_too_small _ =
  let buf = list_to_cstruct [ 0 ] in
  Reader.(match parse_alert buf with
          | Or_error.Ok _    -> assert_failure "short alert passes"
          | Or_error.Error _ -> assert_bool "short alert fails" true)

let alert_too_small2 _ =
  let buf = list_to_cstruct [ 25 ] in
  Reader.(match parse_alert buf with
          | Or_error.Ok _    -> assert_failure "short alert passes"
          | Or_error.Error _ -> assert_bool "short alert fails" true)

let bad_alerts_tests =
  ("short alert" >:: alert_too_small) ::
  ("short alert 2" >:: alert_too_small2) ::
  (List.mapi
     (fun i args -> "Bad alert " ^ string_of_int i >:: bad_alert_parser args)
     bad_alerts)

let good_dhparams = [
  [
    0x01; 0x00; 0xf6; 0x42; 0x57; 0xb7; 0x08; 0x7f; 0x08; 0x17; 0x72; 0xa2; 0xba; 0xd6; 0xa9; 0x42;
    0xf3; 0x05; 0xe8; 0xf9; 0x53; 0x11; 0x39; 0x4f; 0xb6; 0xf1; 0x6e; 0xb9; 0x4b; 0x38; 0x20; 0xda;
    0x01; 0xa7; 0x56; 0xa3; 0x14; 0xe9; 0x8f; 0x40; 0x55; 0xf3; 0xd0; 0x07; 0xc6; 0xcb; 0x43; 0xa9;
    0x94; 0xad; 0xf7; 0x4c; 0x64; 0x86; 0x49; 0xf8; 0x0c; 0x83; 0xbd; 0x65; 0xe9; 0x17; 0xd4; 0xa1;
    0xd3; 0x50; 0xf8; 0xf5; 0x59; 0x5f; 0xdc; 0x76; 0x52; 0x4f; 0x3d; 0x3d; 0x8d; 0xdb; 0xce; 0x99;
    0xe1; 0x57; 0x92; 0x59; 0xcd; 0xfd; 0xb8; 0xae; 0x74; 0x4f; 0xc5; 0xfc; 0x76; 0xbc; 0x83; 0xc5;
    0x47; 0x30; 0x61; 0xce; 0x7c; 0xc9; 0x66; 0xff; 0x15; 0xf9; 0xbb; 0xfd; 0x91; 0x5e; 0xc7; 0x01;
    0xaa; 0xd3; 0x5b; 0x9e; 0x8d; 0xa0; 0xa5; 0x72; 0x3a; 0xd4; 0x1a; 0xf0; 0xbf; 0x46; 0x00; 0x58;
    0x2b; 0xe5; 0xf4; 0x88; 0xfd; 0x58; 0x4e; 0x49; 0xdb; 0xcd; 0x20; 0xb4; 0x9d; 0xe4; 0x91; 0x07;
    0x36; 0x6b; 0x33; 0x6c; 0x38; 0x0d; 0x45; 0x1d; 0x0f; 0x7c; 0x88; 0xb3; 0x1c; 0x7c; 0x5b; 0x2d;
    0x8e; 0xf6; 0xf3; 0xc9; 0x23; 0xc0; 0x43; 0xf0; 0xa5; 0x5b; 0x18; 0x8d; 0x8e; 0xbb; 0x55; 0x8c;
    0xb8; 0x5d; 0x38; 0xd3; 0x34; 0xfd; 0x7c; 0x17; 0x57; 0x43; 0xa3; 0x1d; 0x18; 0x6c; 0xde; 0x33;
    0x21; 0x2c; 0xb5; 0x2a; 0xff; 0x3c; 0xe1; 0xb1; 0x29; 0x40; 0x18; 0x11; 0x8d; 0x7c; 0x84; 0xa7;
    0x0a; 0x72; 0xd6; 0x86; 0xc4; 0x03; 0x19; 0xc8; 0x07; 0x29; 0x7a; 0xca; 0x95; 0x0c; 0xd9; 0x96;
    0x9f; 0xab; 0xd0; 0x0a; 0x50; 0x9b; 0x02; 0x46; 0xd3; 0x08; 0x3d; 0x66; 0xa4; 0x5d; 0x41; 0x9f;
    0x9c; 0x7c; 0xbd; 0x89; 0x4b; 0x22; 0x19; 0x26; 0xba; 0xab; 0xa2; 0x5e; 0xc3; 0x55; 0xe9; 0x32;
    0x0b; 0x3b; 0x00; 0x01; 0x02; 0x01; 0x00; 0x54; 0x7d; 0x06; 0xfb; 0x28; 0xe3; 0x64; 0x86; 0x53;
    0x6e; 0xf0; 0xfc; 0xdc; 0x57; 0xb6; 0x86; 0xae; 0xa7; 0x20; 0xbc; 0xac; 0x76; 0x38; 0xf5; 0x64;
    0x02; 0x9d; 0x19; 0x1a; 0xfe; 0x4d; 0x0d; 0x5a; 0xd3; 0xc6; 0x76; 0x9b; 0x33; 0x8d; 0x3a; 0x96;
    0xcc; 0x3f; 0x72; 0xdf; 0x1d; 0x19; 0xd2; 0x61; 0x41; 0x95; 0x3a; 0x2d; 0x83; 0x7f; 0x4e; 0xbb;
    0x48; 0xf4; 0x77; 0x05; 0xd3; 0x23; 0xff; 0x49; 0xd8; 0xc8; 0x70; 0x0a; 0x69; 0xd4; 0xf7; 0x64;
    0xfa; 0x86; 0x8c; 0x94; 0x96; 0x41; 0x14; 0xf1; 0x6e; 0x6f; 0x09; 0x21; 0x2b; 0xd5; 0xfa; 0x52;
    0x56; 0xf4; 0x44; 0x25; 0x29; 0xb2; 0x51; 0x4e; 0x57; 0xd7; 0x8b; 0xcb; 0x70; 0x3b; 0x94; 0x4f;
    0x2b; 0xe2; 0xa7; 0xfc; 0xaa; 0x09; 0xd0; 0x82; 0x9e; 0xa8; 0x17; 0xbe; 0x84; 0xf0; 0x1a; 0xae;
    0xe1; 0x97; 0x14; 0x7b; 0x74; 0xd4; 0x12; 0xf8; 0x96; 0xbe; 0xa9; 0x2e; 0xdd; 0xbe; 0x28; 0xcd;
    0xe8; 0x9f; 0x67; 0x31; 0x98; 0xcb; 0x74; 0xae; 0xd4; 0x50; 0xa5; 0x77; 0xc4; 0xc1; 0x39; 0x9c;
    0xcd; 0xc2; 0x8a; 0xfe; 0xe2; 0x77; 0x1c; 0x09; 0x75; 0x3e; 0xf7; 0x96; 0x6a; 0x92; 0x96; 0x06;
    0x1e; 0x8d; 0x22; 0xdd; 0x58; 0xfe; 0x3d; 0x84; 0x56; 0x09; 0x17; 0xe2; 0x50; 0xb1; 0xf6; 0x61;
    0x54; 0x6e; 0x5e; 0x94; 0xca; 0xf0; 0x40; 0x68; 0x84; 0xeb; 0xc1; 0x0c; 0x43; 0x3e; 0xbc; 0xb3;
    0x0e; 0x81; 0x4d; 0xc0; 0x21; 0xdb; 0x97; 0xc6; 0x8b; 0x27; 0x10; 0x5c; 0xae; 0xe3; 0x6e; 0x66;
    0x85; 0xaf; 0xff; 0x19; 0x8b; 0xf8; 0xd5; 0x93; 0x4b; 0xd2; 0xd8; 0x7c; 0x64; 0x04; 0xed; 0xce;
    0x88; 0xce; 0xb8; 0x2c; 0x4f; 0xe0; 0xf5; 0x0d; 0x3a; 0xeb; 0x78; 0xee; 0xcf; 0x1a; 0xd1; 0x02;
    0xcf; 0x0f; 0x68; 0xed; 0xd2; 0xca; 0xf6

  ] ; [

    0x01; 0x00; 0xf6; 0x42; 0x57; 0xb7; 0x08; 0x7f; 0x08; 0x17; 0x72; 0xa2; 0xba; 0xd6; 0xa9; 0x42;
    0xf3; 0x05; 0xe8; 0xf9; 0x53; 0x11; 0x39; 0x4f; 0xb6; 0xf1; 0x6e; 0xb9; 0x4b; 0x38; 0x20; 0xda;
    0x01; 0xa7; 0x56; 0xa3; 0x14; 0xe9; 0x8f; 0x40; 0x55; 0xf3; 0xd0; 0x07; 0xc6; 0xcb; 0x43; 0xa9;
    0x94; 0xad; 0xf7; 0x4c; 0x64; 0x86; 0x49; 0xf8; 0x0c; 0x83; 0xbd; 0x65; 0xe9; 0x17; 0xd4; 0xa1;
    0xd3; 0x50; 0xf8; 0xf5; 0x59; 0x5f; 0xdc; 0x76; 0x52; 0x4f; 0x3d; 0x3d; 0x8d; 0xdb; 0xce; 0x99;
    0xe1; 0x57; 0x92; 0x59; 0xcd; 0xfd; 0xb8; 0xae; 0x74; 0x4f; 0xc5; 0xfc; 0x76; 0xbc; 0x83; 0xc5;
    0x47; 0x30; 0x61; 0xce; 0x7c; 0xc9; 0x66; 0xff; 0x15; 0xf9; 0xbb; 0xfd; 0x91; 0x5e; 0xc7; 0x01;
    0xaa; 0xd3; 0x5b; 0x9e; 0x8d; 0xa0; 0xa5; 0x72; 0x3a; 0xd4; 0x1a; 0xf0; 0xbf; 0x46; 0x00; 0x58;
    0x2b; 0xe5; 0xf4; 0x88; 0xfd; 0x58; 0x4e; 0x49; 0xdb; 0xcd; 0x20; 0xb4; 0x9d; 0xe4; 0x91; 0x07;
    0x36; 0x6b; 0x33; 0x6c; 0x38; 0x0d; 0x45; 0x1d; 0x0f; 0x7c; 0x88; 0xb3; 0x1c; 0x7c; 0x5b; 0x2d;
    0x8e; 0xf6; 0xf3; 0xc9; 0x23; 0xc0; 0x43; 0xf0; 0xa5; 0x5b; 0x18; 0x8d; 0x8e; 0xbb; 0x55; 0x8c;
    0xb8; 0x5d; 0x38; 0xd3; 0x34; 0xfd; 0x7c; 0x17; 0x57; 0x43; 0xa3; 0x1d; 0x18; 0x6c; 0xde; 0x33;
    0x21; 0x2c; 0xb5; 0x2a; 0xff; 0x3c; 0xe1; 0xb1; 0x29; 0x40; 0x18; 0x11; 0x8d; 0x7c; 0x84; 0xa7;
    0x0a; 0x72; 0xd6; 0x86; 0xc4; 0x03; 0x19; 0xc8; 0x07; 0x29; 0x7a; 0xca; 0x95; 0x0c; 0xd9; 0x96;
    0x9f; 0xab; 0xd0; 0x0a; 0x50; 0x9b; 0x02; 0x46; 0xd3; 0x08; 0x3d; 0x66; 0xa4; 0x5d; 0x41; 0x9f;
    0x9c; 0x7c; 0xbd; 0x89; 0x4b; 0x22; 0x19; 0x26; 0xba; 0xab; 0xa2; 0x5e; 0xc3; 0x55; 0xe9; 0x32;
    0x0b; 0x3b; 0x00; 0x01; 0x02; 0x01; 0x00; 0x7d; 0x17; 0xb3; 0xc8; 0x40; 0xcd; 0xa0; 0x75; 0x5b;
    0xa4; 0xe1; 0xed; 0xef; 0xd3; 0xed; 0x74; 0x8e; 0x3c; 0xd5; 0x37; 0x17; 0xe2; 0x2b; 0x3d; 0x4e;
    0x20; 0x2b; 0xf4; 0xdc; 0x83; 0x5a; 0x8b; 0x86; 0xed; 0x7b; 0xa3; 0x8d; 0xfa; 0xb4; 0x3a; 0x72;
    0x95; 0xca; 0x5a; 0xd9; 0xf9; 0x27; 0x08; 0x10; 0xec; 0x9b; 0x9b; 0x86; 0xad; 0xbe; 0xfe; 0x77;
    0xcb; 0xf7; 0xf6; 0x03; 0x35; 0x9f; 0x16; 0x97; 0x72; 0x6e; 0x92; 0xb8; 0xd7; 0xd3; 0x09; 0x58;
    0x1d; 0xd0; 0x8a; 0xeb; 0x16; 0xa9; 0x71; 0x9a; 0xf8; 0xb6; 0xc8; 0xcc; 0x63; 0x52; 0x8d; 0x8f;
    0x93; 0x23; 0x1b; 0xa8; 0xfe; 0x3c; 0x17; 0x9b; 0xe6; 0x64; 0x3d; 0xab; 0x57; 0x0c; 0xb1; 0x17;
    0x71; 0xc1; 0x40; 0x72; 0xc9; 0x42; 0x43; 0x68; 0x39; 0xa5; 0x7f; 0x63; 0x03; 0x7e; 0xff; 0xd6;
    0x11; 0xe1; 0x1a; 0xe1; 0xd9; 0x2f; 0xa3; 0x4a; 0x93; 0x4f; 0x09; 0x79; 0xbd; 0x78; 0xf3; 0xf4;
    0xe1; 0x44; 0x7d; 0xaf; 0x7b; 0xd7; 0x82; 0x11; 0xc9; 0xd9; 0x91; 0x01; 0x9a; 0x2c; 0xcb; 0xd1;
    0x41; 0xcc; 0xf5; 0x5c; 0x9f; 0xb5; 0xa2; 0x7c; 0x8b; 0x2d; 0xf6; 0x16; 0xab; 0x68; 0x99; 0x99;
    0x33; 0x80; 0x72; 0xee; 0xce; 0x13; 0xea; 0x3f; 0x62; 0xca; 0xfc; 0x56; 0xd6; 0x6d; 0xa2; 0x8a;
    0xfe; 0xdf; 0x71; 0x7a; 0x82; 0x39; 0xd1; 0x5d; 0x09; 0x27; 0x26; 0x26; 0x5c; 0x6e; 0xab; 0x28;
    0xb2; 0xa1; 0x6f; 0xb9; 0x08; 0x25; 0xd0; 0xa1; 0x68; 0x25; 0x31; 0xae; 0x4a; 0xef; 0x62; 0x99;
    0xb6; 0x4d; 0xd2; 0xa9; 0x27; 0x20; 0x99; 0xc4; 0xdc; 0x44; 0x81; 0x0c; 0xc0; 0xfe; 0xa9; 0xab;
    0xc9; 0xe8; 0x26; 0x00; 0x60; 0x40; 0x0e; 0xb4; 0x07; 0xfc; 0xcf; 0x7f; 0x93; 0xc5; 0x20; 0x10;
    0x49; 0x72; 0xd2; 0x9b; 0x4b; 0x70; 0x03

  ] ; [

    0x01; 0x00; 0xf6; 0x42; 0x57; 0xb7; 0x08; 0x7f; 0x08; 0x17; 0x72; 0xa2; 0xba; 0xd6; 0xa9; 0x42;
    0xf3; 0x05; 0xe8; 0xf9; 0x53; 0x11; 0x39; 0x4f; 0xb6; 0xf1; 0x6e; 0xb9; 0x4b; 0x38; 0x20; 0xda;
    0x01; 0xa7; 0x56; 0xa3; 0x14; 0xe9; 0x8f; 0x40; 0x55; 0xf3; 0xd0; 0x07; 0xc6; 0xcb; 0x43; 0xa9;
    0x94; 0xad; 0xf7; 0x4c; 0x64; 0x86; 0x49; 0xf8; 0x0c; 0x83; 0xbd; 0x65; 0xe9; 0x17; 0xd4; 0xa1;
    0xd3; 0x50; 0xf8; 0xf5; 0x59; 0x5f; 0xdc; 0x76; 0x52; 0x4f; 0x3d; 0x3d; 0x8d; 0xdb; 0xce; 0x99;
    0xe1; 0x57; 0x92; 0x59; 0xcd; 0xfd; 0xb8; 0xae; 0x74; 0x4f; 0xc5; 0xfc; 0x76; 0xbc; 0x83; 0xc5;
    0x47; 0x30; 0x61; 0xce; 0x7c; 0xc9; 0x66; 0xff; 0x15; 0xf9; 0xbb; 0xfd; 0x91; 0x5e; 0xc7; 0x01;
    0xaa; 0xd3; 0x5b; 0x9e; 0x8d; 0xa0; 0xa5; 0x72; 0x3a; 0xd4; 0x1a; 0xf0; 0xbf; 0x46; 0x00; 0x58;
    0x2b; 0xe5; 0xf4; 0x88; 0xfd; 0x58; 0x4e; 0x49; 0xdb; 0xcd; 0x20; 0xb4; 0x9d; 0xe4; 0x91; 0x07;
    0x36; 0x6b; 0x33; 0x6c; 0x38; 0x0d; 0x45; 0x1d; 0x0f; 0x7c; 0x88; 0xb3; 0x1c; 0x7c; 0x5b; 0x2d;
    0x8e; 0xf6; 0xf3; 0xc9; 0x23; 0xc0; 0x43; 0xf0; 0xa5; 0x5b; 0x18; 0x8d; 0x8e; 0xbb; 0x55; 0x8c;
    0xb8; 0x5d; 0x38; 0xd3; 0x34; 0xfd; 0x7c; 0x17; 0x57; 0x43; 0xa3; 0x1d; 0x18; 0x6c; 0xde; 0x33;
    0x21; 0x2c; 0xb5; 0x2a; 0xff; 0x3c; 0xe1; 0xb1; 0x29; 0x40; 0x18; 0x11; 0x8d; 0x7c; 0x84; 0xa7;
    0x0a; 0x72; 0xd6; 0x86; 0xc4; 0x03; 0x19; 0xc8; 0x07; 0x29; 0x7a; 0xca; 0x95; 0x0c; 0xd9; 0x96;
    0x9f; 0xab; 0xd0; 0x0a; 0x50; 0x9b; 0x02; 0x46; 0xd3; 0x08; 0x3d; 0x66; 0xa4; 0x5d; 0x41; 0x9f;
    0x9c; 0x7c; 0xbd; 0x89; 0x4b; 0x22; 0x19; 0x26; 0xba; 0xab; 0xa2; 0x5e; 0xc3; 0x55; 0xe9; 0x32;
    0x0b; 0x3b; 0x00; 0x01; 0x02; 0x01; 0x00; 0x4e; 0x72; 0x1e; 0x54; 0x1d; 0x3b; 0x3c; 0xad; 0xc7;
    0x42; 0xf4; 0x2b; 0xcc; 0xce; 0xc9; 0x71; 0x4a; 0x85; 0xa1; 0x21; 0xda; 0x81; 0x40; 0x6a; 0xeb;
    0x8a; 0x0a; 0x0f; 0xca; 0x73; 0x32; 0x5f; 0xa9; 0x5c; 0x24; 0x21; 0x1d; 0x1d; 0xd6; 0x10; 0xe0;
    0x7f; 0x9e; 0xc4; 0x86; 0x2f; 0xa3; 0xcc; 0xc2; 0x60; 0x5d; 0xed; 0x7f; 0x7d; 0xb7; 0xa2; 0x96;
    0x4f; 0xe6; 0x81; 0x1b; 0x29; 0xf9; 0xf4; 0xc1; 0x00; 0x46; 0x68; 0x4d; 0x72; 0x0e; 0x36; 0x21;
    0xc3; 0x46; 0xf2; 0x81; 0x83; 0xed; 0x30; 0x89; 0x3f; 0xd8; 0x98; 0x39; 0xe5; 0x46; 0x90; 0xeb;
    0x68; 0xe6; 0x3b; 0x8f; 0xc5; 0xd3; 0xa7; 0xfe; 0x87; 0xd7; 0x14; 0x33; 0x5b; 0x70; 0x82; 0x82;
    0x57; 0x2f; 0xd8; 0xb2; 0x91; 0xc3; 0xe5; 0x19; 0x15; 0x5b; 0x76; 0xe6; 0x94; 0x1a; 0xe9; 0x11;
    0x2c; 0xa5; 0x57; 0x55; 0xf0; 0x20; 0x36; 0xc9; 0xe1; 0x32; 0x94; 0x26; 0x47; 0xb8; 0x10; 0x40;
    0xc0; 0x47; 0xf6; 0x66; 0x53; 0x49; 0xe3; 0x85; 0xe1; 0x0e; 0x1e; 0xba; 0xc0; 0xb8; 0x97; 0x8b;
    0x16; 0x8e; 0x48; 0x71; 0xdd; 0x88; 0x3a; 0x8b; 0x21; 0x89; 0xeb; 0x28; 0x8d; 0xaa; 0x97; 0xcf;
    0x4a; 0x45; 0xa4; 0xb8; 0x7d; 0x0f; 0x1e; 0x29; 0xc1; 0xe2; 0xc3; 0x75; 0x43; 0xb5; 0xbf; 0xcf;
    0x14; 0xa4; 0xea; 0x3e; 0xe5; 0x94; 0x0c; 0x32; 0x8a; 0x91; 0xcb; 0x47; 0x7f; 0x23; 0x5b; 0xe9;
    0x79; 0x96; 0x7c; 0xdb; 0xbc; 0x32; 0xce; 0x96; 0xb5; 0x34; 0x68; 0x94; 0xbf; 0x4f; 0xd7; 0x16;
    0x74; 0x4c; 0x52; 0xf2; 0x04; 0xfb; 0x6a; 0xe6; 0xb9; 0x07; 0x7c; 0x8f; 0x62; 0xdf; 0x13; 0xb7;
    0x3e; 0xd6; 0x85; 0x12; 0x46; 0xfd; 0xb8; 0x2b; 0x30; 0x5e; 0x16; 0x25; 0x8e; 0x2a; 0x20; 0x01;
    0x07; 0xe8; 0x5f; 0x0d; 0x77; 0x08; 0xd5

  ] ; [

      0x00; 0x80; 0xbb; 0xbc; 0x2d; 0xca; 0xd8; 0x46; 0x74; 0x90; 0x7c; 0x43; 0xfc; 0xf5; 0x80; 0xe9;
      0xcf; 0xdb; 0xd9; 0x58; 0xa3; 0xf5; 0x68; 0xb4; 0x2d; 0x4b; 0x08; 0xee; 0xd4; 0xeb; 0x0f; 0xb3;
      0x50; 0x4c; 0x6c; 0x03; 0x02; 0x76; 0xe7; 0x10; 0x80; 0x0c; 0x5c; 0xcb; 0xba; 0xa8; 0x92; 0x26;
      0x14; 0xc5; 0xbe; 0xec; 0xa5; 0x65; 0xa5; 0xfd; 0xf1; 0xd2; 0x87; 0xa2; 0xbc; 0x04; 0x9b; 0xe6;
      0x77; 0x80; 0x60; 0xe9; 0x1a; 0x92; 0xa7; 0x57; 0xe3; 0x04; 0x8f; 0x68; 0xb0; 0x76; 0xf7; 0xd3;
      0x6c; 0xc8; 0xf2; 0x9b; 0xa5; 0xdf; 0x81; 0xdc; 0x2c; 0xa7; 0x25; 0xec; 0xe6; 0x62; 0x70; 0xcc;
      0x9a; 0x50; 0x35; 0xd8; 0xce; 0xce; 0xef; 0x9e; 0xa0; 0x27; 0x4a; 0x63; 0xab; 0x1e; 0x58; 0xfa;
      0xfd; 0x49; 0x88; 0xd0; 0xf6; 0x5d; 0x14; 0x67; 0x57; 0xda; 0x07; 0x1d; 0xf0; 0x45; 0xcf; 0xe1;
      0x6b; 0x9b; 0x00; 0x01; 0x02; 0x00; 0x80; 0x4a; 0x2d; 0x33; 0x76; 0x4d; 0x32; 0x70; 0xf1; 0x94;
      0x1a; 0xc1; 0x35; 0x63; 0x97; 0x62; 0xca; 0xcc; 0xd6; 0x2d; 0xfd; 0x23; 0x2d; 0x3a; 0x71; 0x03;
      0xc4; 0x9d; 0x42; 0x93; 0x78; 0x8c; 0x32; 0xc4; 0x8b; 0x0d; 0xad; 0xdd; 0xe2; 0x30; 0x96; 0xf1;
      0xb9; 0xef; 0x16; 0x72; 0x2e; 0x6d; 0x1f; 0xb9; 0x92; 0x5d; 0x17; 0xc5; 0x0f; 0x2b; 0x07; 0xc8;
      0xae; 0xf7; 0x60; 0x3d; 0x53; 0x62; 0x2e; 0xb5; 0xe3; 0x0b; 0x20; 0x67; 0xb1; 0xdf; 0x57; 0x14;
      0x59; 0xff; 0xca; 0xe6; 0x72; 0x5d; 0xd7; 0x1a; 0x98; 0x1e; 0xa1; 0x2b; 0xce; 0xf7; 0x9e; 0xcf;
      0x45; 0x41; 0xa4; 0xa8; 0xdc; 0x98; 0xf7; 0x0d; 0x98; 0xf3; 0x47; 0x7a; 0xe3; 0x25; 0x41; 0x02;
      0x31; 0x26; 0x1f; 0x4d; 0xbb; 0x36; 0xcd; 0xcc; 0x64; 0x74; 0xae; 0xb5; 0x19; 0xd9; 0xa3; 0xd6;
      0x89; 0x6f; 0x9d; 0x02; 0xd4; 0x52; 0xdd

    ] ; [

      0x00; 0x80; 0xbb; 0xbc; 0x2d; 0xca; 0xd8; 0x46; 0x74; 0x90; 0x7c; 0x43; 0xfc; 0xf5; 0x80; 0xe9;
      0xcf; 0xdb; 0xd9; 0x58; 0xa3; 0xf5; 0x68; 0xb4; 0x2d; 0x4b; 0x08; 0xee; 0xd4; 0xeb; 0x0f; 0xb3;
      0x50; 0x4c; 0x6c; 0x03; 0x02; 0x76; 0xe7; 0x10; 0x80; 0x0c; 0x5c; 0xcb; 0xba; 0xa8; 0x92; 0x26;
      0x14; 0xc5; 0xbe; 0xec; 0xa5; 0x65; 0xa5; 0xfd; 0xf1; 0xd2; 0x87; 0xa2; 0xbc; 0x04; 0x9b; 0xe6;
      0x77; 0x80; 0x60; 0xe9; 0x1a; 0x92; 0xa7; 0x57; 0xe3; 0x04; 0x8f; 0x68; 0xb0; 0x76; 0xf7; 0xd3;
      0x6c; 0xc8; 0xf2; 0x9b; 0xa5; 0xdf; 0x81; 0xdc; 0x2c; 0xa7; 0x25; 0xec; 0xe6; 0x62; 0x70; 0xcc;
      0x9a; 0x50; 0x35; 0xd8; 0xce; 0xce; 0xef; 0x9e; 0xa0; 0x27; 0x4a; 0x63; 0xab; 0x1e; 0x58; 0xfa;
      0xfd; 0x49; 0x88; 0xd0; 0xf6; 0x5d; 0x14; 0x67; 0x57; 0xda; 0x07; 0x1d; 0xf0; 0x45; 0xcf; 0xe1;
      0x6b; 0x9b; 0x00; 0x01; 0x02; 0x00; 0x80; 0x0c; 0x00; 0xda; 0x79; 0x24; 0x02; 0x33; 0x29; 0xf5;
      0x81; 0xc4; 0x67; 0x5a; 0x03; 0x2b; 0xbf; 0xaf; 0xd6; 0x76; 0xdd; 0x26; 0xdc; 0xd4; 0x38; 0x35;
      0xc1; 0x7f; 0x3a; 0x9e; 0x02; 0x31; 0x73; 0x17; 0xf2; 0x68; 0x5f; 0xd4; 0xf0; 0x6a; 0x97; 0x51;
      0xb2; 0x42; 0xb4; 0x8d; 0x35; 0x89; 0x29; 0x96; 0x27; 0xf7; 0x89; 0x59; 0x9b; 0x93; 0xb0; 0x4f;
      0x85; 0x28; 0xfa; 0x10; 0xe7; 0x15; 0x09; 0x71; 0x10; 0x36; 0x01; 0x60; 0xcf; 0xe0; 0x37; 0xbb;
      0xfd; 0xcd; 0xc3; 0x9e; 0x27; 0xf8; 0xf4; 0x90; 0xcd; 0x87; 0xd9; 0x5c; 0x92; 0x08; 0x44; 0x32;
      0xb5; 0x2b; 0xe2; 0xa5; 0x72; 0xde; 0x97; 0x0c; 0x4f; 0xc7; 0x60; 0x8d; 0xe7; 0xcf; 0x64; 0xba;
      0x7e; 0x0d; 0x0f; 0x91; 0x58; 0x0d; 0x47; 0x6c; 0x3f; 0xb8; 0x4f; 0xb9; 0x02; 0xc5; 0xcc; 0x72;
      0x33; 0x33; 0xde; 0xf2; 0x8f; 0x6b; 0x8c

    ] ; [

        0x00; 0x80; 0xbb; 0xbc; 0x2d; 0xca; 0xd8; 0x46; 0x74; 0x90; 0x7c; 0x43; 0xfc; 0xf5; 0x80; 0xe9;
        0xcf; 0xdb; 0xd9; 0x58; 0xa3; 0xf5; 0x68; 0xb4; 0x2d; 0x4b; 0x08; 0xee; 0xd4; 0xeb; 0x0f; 0xb3;
        0x50; 0x4c; 0x6c; 0x03; 0x02; 0x76; 0xe7; 0x10; 0x80; 0x0c; 0x5c; 0xcb; 0xba; 0xa8; 0x92; 0x26;
        0x14; 0xc5; 0xbe; 0xec; 0xa5; 0x65; 0xa5; 0xfd; 0xf1; 0xd2; 0x87; 0xa2; 0xbc; 0x04; 0x9b; 0xe6;
        0x77; 0x80; 0x60; 0xe9; 0x1a; 0x92; 0xa7; 0x57; 0xe3; 0x04; 0x8f; 0x68; 0xb0; 0x76; 0xf7; 0xd3;
        0x6c; 0xc8; 0xf2; 0x9b; 0xa5; 0xdf; 0x81; 0xdc; 0x2c; 0xa7; 0x25; 0xec; 0xe6; 0x62; 0x70; 0xcc;
        0x9a; 0x50; 0x35; 0xd8; 0xce; 0xce; 0xef; 0x9e; 0xa0; 0x27; 0x4a; 0x63; 0xab; 0x1e; 0x58; 0xfa;
        0xfd; 0x49; 0x88; 0xd0; 0xf6; 0x5d; 0x14; 0x67; 0x57; 0xda; 0x07; 0x1d; 0xf0; 0x45; 0xcf; 0xe1;
        0x6b; 0x9b; 0x00; 0x01; 0x02; 0x00; 0x80; 0x7e; 0x8f; 0xc7; 0x38; 0x8a; 0xf8; 0xdd; 0x7a; 0xb2;
        0x0a; 0x07; 0xdd; 0x00; 0xfb; 0x63; 0x58; 0x85; 0xde; 0xc7; 0x6a; 0xe0; 0x0a; 0x51; 0x06; 0x7b;
        0x3e; 0xfd; 0xac; 0xfe; 0xe2; 0x7a; 0xf7; 0x3f; 0xcb; 0xb2; 0xfc; 0x30; 0x45; 0xfa; 0x2b; 0x74;
        0xb7; 0x2f; 0xf5; 0xf9; 0x52; 0xef; 0x93; 0x3f; 0xdb; 0x7e; 0x00; 0xe7; 0xd4; 0xa4; 0x20; 0xbe;
        0x2d; 0x6f; 0xde; 0x28; 0x6c; 0x74; 0x8b; 0x23; 0xc6; 0x14; 0xdc; 0xb9; 0x24; 0xca; 0x87; 0xe0;
        0xe9; 0x5e; 0xb0; 0x4e; 0x55; 0x74; 0x54; 0x4d; 0x8a; 0x21; 0x26; 0x62; 0x28; 0x2a; 0xe6; 0xb1;
        0x29; 0xdc; 0xcd; 0xda; 0x27; 0xc4; 0xcd; 0x8d; 0xd3; 0x47; 0x40; 0x05; 0x1f; 0xbb; 0x80; 0xef;
        0xa0; 0xf4; 0x5a; 0x22; 0x7c; 0x4a; 0xe5; 0xb0; 0x59; 0x68; 0xa5; 0x3e; 0xbb; 0x6f; 0x62; 0x30;
        0x20; 0xc1; 0x43; 0x91; 0xd2; 0x79; 0xf5

     ] ; [

        0x00; 0x80; 0xbb; 0xbc; 0x2d; 0xca; 0xd8; 0x46; 0x74; 0x90; 0x7c; 0x43; 0xfc; 0xf5; 0x80; 0xe9;
        0xcf; 0xdb; 0xd9; 0x58; 0xa3; 0xf5; 0x68; 0xb4; 0x2d; 0x4b; 0x08; 0xee; 0xd4; 0xeb; 0x0f; 0xb3;
        0x50; 0x4c; 0x6c; 0x03; 0x02; 0x76; 0xe7; 0x10; 0x80; 0x0c; 0x5c; 0xcb; 0xba; 0xa8; 0x92; 0x26;
        0x14; 0xc5; 0xbe; 0xec; 0xa5; 0x65; 0xa5; 0xfd; 0xf1; 0xd2; 0x87; 0xa2; 0xbc; 0x04; 0x9b; 0xe6;
        0x77; 0x80; 0x60; 0xe9; 0x1a; 0x92; 0xa7; 0x57; 0xe3; 0x04; 0x8f; 0x68; 0xb0; 0x76; 0xf7; 0xd3;
        0x6c; 0xc8; 0xf2; 0x9b; 0xa5; 0xdf; 0x81; 0xdc; 0x2c; 0xa7; 0x25; 0xec; 0xe6; 0x62; 0x70; 0xcc;
        0x9a; 0x50; 0x35; 0xd8; 0xce; 0xce; 0xef; 0x9e; 0xa0; 0x27; 0x4a; 0x63; 0xab; 0x1e; 0x58; 0xfa;
        0xfd; 0x49; 0x88; 0xd0; 0xf6; 0x5d; 0x14; 0x67; 0x57; 0xda; 0x07; 0x1d; 0xf0; 0x45; 0xcf; 0xe1;
        0x6b; 0x9b; 0x00; 0x01; 0x02; 0x00; 0x80; 0x73; 0x47; 0x2a; 0xde; 0x22; 0x94; 0x39; 0x77; 0x46;
        0x25; 0xe2; 0x2d; 0x4f; 0x8d; 0x9e; 0x99; 0x10; 0xa2; 0x1a; 0xd6; 0xf1; 0xe6; 0x25; 0x7f; 0x76;
        0xbe; 0x87; 0xf6; 0xff; 0xce; 0x7d; 0xd7; 0xd2; 0xee; 0xc5; 0x01; 0x0b; 0x14; 0xa1; 0xda; 0x0a;
        0x56; 0x4f; 0xff; 0x8c; 0xdd; 0x84; 0x7c; 0xd8; 0xcc; 0xa8; 0xc1; 0xc3; 0xa1; 0xbf; 0x15; 0x38;
        0xc9; 0x4f; 0xc3; 0x7b; 0xde; 0xf3; 0x37; 0xf3; 0x2f; 0x8e; 0x72; 0x4d; 0xfb; 0x69; 0xc6; 0x4d;
        0xe4; 0x84; 0x46; 0x64; 0xe1; 0xb5; 0x02; 0xe8; 0xf9; 0xbd; 0x94; 0xbf; 0x40; 0x5e; 0x1f; 0xb6;
        0x39; 0xb9; 0x0b; 0x1a; 0x79; 0xf1; 0xa6; 0x3d; 0xee; 0x7a; 0x02; 0xff; 0x62; 0x0d; 0xc6; 0x1e;
        0xfb; 0x5a; 0xcd; 0x36; 0xee; 0x6d; 0x67; 0x5f; 0x81; 0xf4; 0xde; 0x62; 0x15; 0xb6; 0x9a; 0xf3;
        0x24; 0xa2; 0xb3; 0x95; 0xdf; 0x6a; 0xa2

      ]
]

let good_dh_param_parser xs _ =
  let buf = list_to_cstruct xs in
  Reader.(match parse_dh_parameters buf with
          | Or_error.Error _          -> assert_failure "dh params parser broken"
          | Or_error.Ok (p, raw, rst) -> assert_equal 0 (Cstruct.len rst))

let good_dh_params_tests =
  List.mapi
    (fun i f -> "Parse good dh_param " ^ string_of_int i >:: good_dh_param_parser f)
    good_dhparams

let bad_dh_param_parser buf _ =
  Reader.(match parse_dh_parameters buf with
          | Or_error.Error _ -> assert_bool "dh parser" true
          | Or_error.Ok (p, raw, rst) ->
             if Cstruct.len rst == 0 then
               assert_failure "dh params parser broken"
             else
               assert_bool "dh parser" true)

let bad_dh_params_tests =
  let param = list_to_cstruct (List.hd good_dhparams) in
  let l = Cstruct.len param in
  let bad_params =
    [
      param <> Cstruct.create 1 ;
      Cstruct.sub param 2 20 ;
      Cstruct.sub param 0 20 ;
      list_to_cstruct [2]  <> param ;
      list_to_cstruct [0]  <> param ;
      list_to_cstruct [0; 1]  <> param ;
      list_to_cstruct [0; 0]  <> param ;
      list_to_cstruct [0xff; 0xff]  <> param ;
      list_to_cstruct [0; 0xff]  <> param ;
      Cstruct.shift param 1 ;
      Cstruct.sub param 0 (pred l)
    ]
  in
  let lastparam = list_to_cstruct (List.nth good_dhparams 5) in
  let l = Cstruct.len lastparam in
  let more_bad =
    [
      Cstruct.sub lastparam 0 130 <> list_to_cstruct [0 ; 5 ; 1] <> Cstruct.sub lastparam 130 (l - 130) ;
      Cstruct.sub lastparam 0 133 <> list_to_cstruct [0 ; 5 ; 1] <> Cstruct.sub lastparam 133 (l - 133)
    ]
  in
  List.mapi
    (fun i f -> "Parse bad dh_param " ^ string_of_int i >:: bad_dh_param_parser f)
    (bad_params @ more_bad)


(*
==============================
digitally signed
06 01 01 00 30 92 f4 70 b1 02 0a 51 b6 0e 49 1e 
16 6d 9f b5 fe 73 5e 2f 18 bc f7 87 ab 2c ad 7e 
54 40 99 30 a2 2e 55 e0 f3 05 e1 81 67 78 49 29 
e6 5d 2c 64 57 eb 8c 68 24 e1 ba 69 50 c7 da 73 
9a 02 e4 bc c0 76 65 af 31 93 bc 2f 5c db a5 1d 
4e b2 75 0d b4 22 23 05 5b 8c a0 14 4c 64 b9 91 
a6 22 c2 49 aa 41 b0 42 04 2a 03 03 1e 62 74 64 
98 af cf 9a d0 22 a8 f3 a5 0a 0d e9 dc e2 89 e5 
54 a2 28 25 69 4e e5 c3 a6 23 d2 eb 67 8a b8 4a 
ac 19 1d 00 a9 ec ca eb f9 79 2c 7c 6e 31 7f 64 
64 a2 fb 93 c5 91 a2 ad 8e 36 07 e8 51 0b 08 36 
b7 78 ac 21 3d c9 fb ae ab e5 d9 9c a7 ee 5e cb 
ab 57 9d 62 6c 2e bd 6d 4a d0 36 b1 a8 f1 22 d8 
97 5c 24 b3 72 55 20 39 29 26 51 3b 9c 48 80 25 
a9 f4 c1 b0 57 d8 3f 54 5e 99 27 36 81 cd 23 f6 
aa 84 98 f8 66 79 e1 16 b9 eb c6 9a 86 90 a6 a2 
9d 0d 86 32 
==============================

==============================
digitally signed
06 01 01 00 8e 02 51 93 67 e8 68 fe 65 61 da f0 
25 1a 19 5a 36 42 11 dd 00 2b f2 38 98 ef 94 42 
ac 3d 82 c7 85 72 f3 b7 73 4d 6b 64 66 6a 89 6d 
95 67 db b7 83 1e b1 7c f4 b9 60 bd 91 26 e0 4c 
6c 92 c7 c4 8b b5 8d af fd aa d9 cc 2f af 6b 18 
f7 4f cd 8d 54 e1 70 5c a9 ec 85 d9 7b 5b a2 9a 
55 c2 5a 87 d4 be 49 f2 03 95 50 5f 62 a7 4d 13 
29 ae 19 cc 2e 21 9b 36 60 c4 d7 5a 8f e2 67 73 
22 85 66 bb 00 00 97 10 bc 19 16 ce 14 8e 27 1e 
79 3e bd c3 c9 5c c2 bf 7b 83 ba 00 20 18 54 0b 
09 11 b3 0b 75 7d f6 c7 80 76 25 3c 3b db 67 c5 
e7 77 0a e1 bf d9 c2 6c c2 3f 37 4b cf 6c 64 53 
4a f3 81 6d d8 13 ce b4 84 42 7b 73 85 11 aa 0e 
39 d8 99 76 5e e8 e0 bc 08 e6 7b ba c9 6e dd 63 
38 ca 5b 8b 74 ed 52 04 e3 64 e6 dc fa 1d 46 ca 
5d f8 18 3e a7 39 7e 19 b9 2f 87 5b 2a 55 85 e5 
9e 92 6b 62 
==============================

==============================
digitally signed
06 01 01 00 2b 5b 89 fa 67 4b 58 45 d4 8f 22 4b 
53 3b 92 2b 37 18 cd 05 da b5 85 11 23 12 dc 18 
b5 9f b0 45 16 f3 1c f8 93 b8 8c 37 d5 60 68 ee 
75 53 a9 5f 22 4e 01 2b b3 b6 3e 29 ba 2c ef a8 
3f 07 a3 fb 91 f8 2c 8d 23 e3 8d 26 26 11 a4 d9 
a0 a4 10 11 40 1a ad c3 a4 99 5a ae 97 ae 9b 39 
dc 98 b3 34 e7 08 b4 5f ae a1 f7 79 92 d3 8d 23 
47 a4 8d a8 1a 4a ae 10 d7 f8 e0 7a f4 52 5a b0 
c3 6f 5a 8a 94 75 bf 27 c1 bb b0 5c 66 66 60 0d 
dd a8 cf 1b ee 6f 33 63 ec aa 16 15 3a cc 72 6f 
9e c1 06 f3 45 ec 7f 6b 17 ab ce 63 15 8c 0e 61 
98 d9 c4 68 ba 56 88 0a 46 cc 0c d9 09 ea 8f db 
28 35 16 a2 5d fb c2 93 f3 a5 53 e4 94 da 45 a9 
81 0c 43 45 67 ef 70 4a 06 67 b1 b6 30 19 16 b1 
eb 28 3c 8b 13 94 1a 79 8c 92 7b e0 fb ea d1 fc 
50 f8 b7 86 76 a1 69 81 3e b1 88 f5 a7 05 e9 e1 
d1 9e bc 15 
==============================

==============================
digitally signed
06 01 01 00 6c 1b e8 31 7b ab 2b 5f a0 9f 6d 73 
43 83 67 d2 85 ae 85 56 65 6a f9 82 c0 29 48 28 
9d d9 2a 23 ea 8d 0c c2 9e 8f 84 b6 74 5d af df 
0a 39 5f 4a 2c a0 b8 02 20 a6 33 3f 22 2b 38 49 
5f 21 ea 62 1a 73 e4 0a 1f f5 e0 89 8c b3 dd f4 
ef c8 35 8f 60 a2 4c 95 f7 cb 8e 1f f0 15 f4 22 
01 97 b0 59 4e 59 40 7c 43 df 1c 35 5f 8d de 26 
77 0d 47 ec 84 30 7f 0e f3 17 3b 26 8b 35 9d e2 
02 49 82 a4 4e 0d b2 d9 5f 83 55 8d 56 b2 7e 33 
11 9f 50 fb f3 af a6 96 90 52 76 ea bd 03 de 5c 
3a d7 4f 1c 89 e6 b0 a3 39 8a b1 70 b9 1f 2f 25 
03 e5 d6 87 36 62 ea 4a 8a 60 b5 83 20 62 d5 58 
7e 94 19 42 4d c7 48 b2 fb ed fb d1 c4 fe 7f 48 
f9 e2 d4 15 d1 2c e1 73 76 77 bf 0c 5a c3 8b c2 
6a d7 58 ce eb 96 58 55 fb 35 5a 8d 82 aa 2e 7d 
0e d3 8d b9 6a fe 02 c3 bc d2 43 e9 4e 72 e6 bd 
d2 49 63 c5 
==============================

==============================
digitally signed
06 01 01 00 23 8d 01 f7 ce e3 e9 f8 b4 43 5a 48 
4c 98 45 57 45 7a 70 6f 02 f9 3e 18 16 32 ce 48 
49 3d 1b ed bd 96 73 b7 b1 26 df 07 6c 2a d0 c4 
c9 7d 79 cc 06 b4 9a 56 17 43 e5 0d e6 69 d1 bb 
e5 f5 c7 9a 2e ed ec 97 c9 53 b0 ab c6 37 99 2f 
bc e5 9b d7 a2 eb d8 88 29 cf 6f 35 64 d0 40 ed 
dd cd 12 9a 93 b0 6c de 75 89 5b 19 7b bb e7 4f 
cf 6f 87 85 8a b8 b3 1e d2 c3 60 51 2c 5b eb e3 
77 40 84 75 4f 97 1a 55 67 f6 75 5b ec 61 96 30 
0f 41 c4 02 63 05 52 c8 76 2a 0b 23 6e 97 1f 16 
b6 68 92 c6 2f 9b 1c e2 2f f6 02 90 1a 51 a7 49 
43 41 31 22 3f 9a d1 e7 d0 6b e4 82 1f bd 93 ca 
af 5d f5 05 f3 9a b8 3d 19 21 8d 0b 20 00 5a 21 
5f 8e 1a 77 d0 70 fb 8c 98 9d 63 b3 9a 6a 3f c3 
89 43 fe 1c a7 6f b6 d6 1f a9 3e 6c e2 7a 8e 31 
bc 8f 4e e4 c0 36 8d 72 01 f4 65 71 ff 16 a6 c7 
0a 59 f1 18 
==============================
 *)


let suite =
  "All" >::: [
    "Reader" >:::
      version_tests @
      good_headers_tests @ bad_headers_tests @
      good_alert_tests @ bad_alerts_tests @
      good_dh_params_tests @ bad_dh_params_tests
  ]

