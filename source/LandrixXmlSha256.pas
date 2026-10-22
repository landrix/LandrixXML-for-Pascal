{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  SHA-256 (FIPS 180-4), for the source fingerprint of compiled Schematron
  rules. The 32-bit arithmetic goes through Int64 and masks, so that it
  is correct with overflow and range checks on and on 64-bit targets. }

unit LandrixXmlSha256;

{$I LandrixXml.inc}

interface

{ The SHA-256 of Size bytes at Data as 64 lowercase hex digits; a
  negative Size raises ELandrixXmlError (xecInvalidArgument). }
function LandrixXmlSha256Hex(const Data; Size: Integer): string;

implementation

uses
  LandrixXmlBase;

type
  TWords = array[0..63] of Cardinal;
  TState = array[0..7] of Cardinal;
  TBlock = array[0..63] of Byte;

const
  K: array[0..63] of Cardinal = (
    $428A2F98, $71374491, $B5C0FBCF, $E9B5DBA5, $3956C25B, $59F111F1, $923F82A4, $AB1C5ED5,
    $D807AA98, $12835B01, $243185BE, $550C7DC3, $72BE5D74, $80DEB1FE, $9BDC06A7, $C19BF174,
    $E49B69C1, $EFBE4786, $0FC19DC6, $240CA1CC, $2DE92C6F, $4A7484AA, $5CB0A9DC, $76F988DA,
    $983E5152, $A831C66D, $B00327C8, $BF597FC7, $C6E00BF3, $D5A79147, $06CA6351, $14292967,
    $27B70A85, $2E1B2138, $4D2C6DFC, $53380D13, $650A7354, $766A0ABB, $81C2C92E, $92722C85,
    $A2BFE8A1, $A81A664B, $C24B8B70, $C76C51A3, $D192E819, $D6990624, $F40E3585, $106AA070,
    $19A4C116, $1E376C08, $2748774C, $34B0BCB5, $391C0CB3, $4ED8AA4A, $5B9CCA4F, $682E6FF3,
    $748F82EE, $78A5636F, $84C87814, $8CC70208, $90BEFFFA, $A4506CEB, $BEF9A3F7, $C67178F2);

  Initial: TState = ($6A09E667, $BB67AE85, $3C6EF372, $A54FF53A, $510E527F, $9B05688C, $1F83D9AB,
    $5BE0CD19);

function Add(A, B: Cardinal): Cardinal;
begin
  Result := Cardinal((Int64(A) + Int64(B)) and $FFFFFFFF);
end;

function RotR(X: Cardinal; N: Integer): Cardinal;
begin
  Result := Cardinal(((Int64(X) shr N) or (Int64(X) shl (32 - N))) and $FFFFFFFF);
end;

function ShiftRight(X: Cardinal; N: Integer): Cardinal;
begin
  Result := Cardinal(Int64(X) shr N);
end;

procedure Compress(var H: TState; const Block: TBlock);
var
  W: TWords;
  A, B, C, D, E, F, G, HH, S0, S1, Ch, Maj, T1, T2: Cardinal;
  I: Integer;
begin
  for I := 0 to 15 do
    W[I] := Cardinal((Int64(Block[4 * I]) shl 24) or (Int64(Block[4 * I + 1]) shl 16) or
      (Int64(Block[4 * I + 2]) shl 8) or Int64(Block[4 * I + 3]));
  for I := 16 to 63 do
  begin
    S0 := RotR(W[I - 15], 7) xor RotR(W[I - 15], 18) xor ShiftRight(W[I - 15], 3);
    S1 := RotR(W[I - 2], 17) xor RotR(W[I - 2], 19) xor ShiftRight(W[I - 2], 10);
    W[I] := Add(Add(W[I - 16], S0), Add(W[I - 7], S1));
  end;
  A := H[0];
  B := H[1];
  C := H[2];
  D := H[3];
  E := H[4];
  F := H[5];
  G := H[6];
  HH := H[7];
  for I := 0 to 63 do
  begin
    S1 := RotR(E, 6) xor RotR(E, 11) xor RotR(E, 25);
    { (E and F) xor ((not E) and G), without "not" on a Cardinal }
    Ch := G xor (E and (F xor G));
    T1 := Add(Add(Add(HH, S1), Add(Ch, K[I])), W[I]);
    S0 := RotR(A, 2) xor RotR(A, 13) xor RotR(A, 22);
    Maj := (A and B) xor (A and C) xor (B and C);
    T2 := Add(S0, Maj);
    HH := G;
    G := F;
    F := E;
    E := Add(D, T1);
    D := C;
    C := B;
    B := A;
    A := Add(T1, T2);
  end;
  H[0] := Add(H[0], A);
  H[1] := Add(H[1], B);
  H[2] := Add(H[2], C);
  H[3] := Add(H[3], D);
  H[4] := Add(H[4], E);
  H[5] := Add(H[5], F);
  H[6] := Add(H[6], G);
  H[7] := Add(H[7], HH);
end;

function LandrixXmlSha256Hex(const Data; Size: Integer): string;
const
  Digits = '0123456789abcdef';
var
  H: TState;
  P: PAnsiChar;
  Block: TBlock;
  I, J, Done, Rest: Integer;
  Bits: Int64;
begin
  if Size < 0 then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'SHA-256 of a negative size');
  H := Initial;
  P := PAnsiChar(@Data);
  Done := 0;
  while Size - Done >= 64 do
  begin
    for I := 0 to 63 do
      Block[I] := Ord(P[Done + I]);
    Compress(H, Block);
    Inc(Done, 64);
  end;
  { the rest, a 1 bit, zeros and the length in bits (big endian) }
  Rest := Size - Done;
  for I := 0 to 63 do
    Block[I] := 0;
  for I := 0 to Rest - 1 do
    Block[I] := Ord(P[Done + I]);
  Block[Rest] := $80;
  if Rest >= 56 then
  begin
    Compress(H, Block);
    for I := 0 to 63 do
      Block[I] := 0;
  end;
  Bits := Int64(Size) * 8;
  for I := 0 to 7 do
    Block[63 - I] := Byte((Bits shr (8 * I)) and $FF);
  Compress(H, Block);
  Result := '';
  for I := 0 to 7 do
    for J := 7 downto 0 do
      Result := Result + Digits[Integer((H[I] shr (4 * J)) and $F) + 1];
end;

end.
