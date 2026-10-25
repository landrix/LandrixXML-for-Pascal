{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  xs:double for the validation units (IEEE 754 binary64): arithmetic,
  comparison, rounding, lexical parsing with correct rounding, the XPath
  string value (shortest digits, as Saxon prints doubles) and the exact
  conversions between xs:double and xs:decimal; xs:float (binary32) as a
  TLandrixXmlDouble restricted to binary32 values.

  Everything is computed in software on the bit pattern with integer
  arithmetic: every operation is first done exactly and then rounded once
  to nearest, ties to even. Results are therefore identical on every
  compiler and CPU, independent of the x87 precision control, and no
  floating-point exception is ever raised (1 / 0 gives INF, 0 / 0 NaN).
  Values are carried as TLandrixXmlDouble, never as a native Double, so the
  FPU is not involved at all; LandrixXmlDoubleFromNative and ...ToNative
  convert at the boundary. There is a single NaN (bit pattern
  7FF8000000000000), as XPath knows only one.

  Errors raise ELandrixXmlError with xecConversion (invalid lexical form,
  NaN or infinity converted to xs:decimal or xs:integer).

  The names start with LandrixXmlDouble (LandrixXmlDoubleParse, not
  LandrixXmlParseDouble) because LandrixXmlConvert already has
  LandrixXmlParseDouble and LandrixXmlFormatDouble for native doubles. }

unit LandrixXmlDouble;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  LandrixXmlBase,
  LandrixXmlDecimal;

const
  { Result of LandrixXmlDoubleCompare when an operand is NaN. }
  LandrixXmlDoubleUnordered = 2;

type
  { An IEEE 754 binary64 value as its bit pattern. Build values with the
    functions below; a NaN must always be the canonical pattern. }
  TLandrixXmlDouble = record
    Bits: Int64;
  end;

function LandrixXmlDoubleFromBits(Bits: Int64): TLandrixXmlDouble;
{ Native Double <-> TLandrixXmlDouble by bit copy (any NaN becomes the
  canonical one). }
function LandrixXmlDoubleFromNative(const Value: Double): TLandrixXmlDouble;
function LandrixXmlDoubleToNative(const A: TLandrixXmlDouble): Double;

function LandrixXmlDoubleNaN: TLandrixXmlDouble;
function LandrixXmlDoubleInfinity(Negative: Boolean): TLandrixXmlDouble;
function LandrixXmlDoubleZero(Negative: Boolean): TLandrixXmlDouble;

function LandrixXmlDoubleIsNaN(const A: TLandrixXmlDouble): Boolean;
function LandrixXmlDoubleIsInfinite(const A: TLandrixXmlDouble): Boolean;
{ True for +0 and -0. }
function LandrixXmlDoubleIsZero(const A: TLandrixXmlDouble): Boolean;
{ True for negative values including -0 and -INF; False for NaN. }
function LandrixXmlDoubleSignBit(const A: TLandrixXmlDouble): Boolean;

{ xs:double lexical form: optional sign, digits with an optional '.', an
  optional exponent (e or E, optional sign, digits), or INF, +INF, -INF,
  NaN. Leading and trailing XML white space is ignored. The result is the
  nearest double (ties to even); values beyond the range give +-INF,
  values below half of the smallest subnormal give +-0. }
function LandrixXmlDoubleTryParse(const S: TLandrixXmlUtf8; out Value: TLandrixXmlDouble): Boolean;
{ Like LandrixXmlDoubleTryParse, but raises ELandrixXmlError (xecConversion). }
function LandrixXmlDoubleParse(const S: TLandrixXmlUtf8): TLandrixXmlDouble;

{ The XPath string value as Saxon HE 12 writes it: plain notation for
  1E-6 <= |A| < 1E6 ("0.1", "123456.7", "100"), else scientific notation
  ("1.0E6", "1.2345E-7"); "0", "-0", "NaN", "INF", "-INF". The digits are
  Saxon's (see SaxonDigits in the implementation): usually the shortest
  that read back, with Saxon's quirks reproduced (1E23 gives
  "0.9999999999999999E23"). Subnormal numbers get the shortest digits,
  while Saxon on Java 17 sometimes writes one digit more for them. }
function LandrixXmlDoubleFormat(const A: TLandrixXmlDouble): TLandrixXmlUtf8;

{ The exact decimal value of a finite double (the cast xs:decimal(double):
  0.1e0 gives 0.1000000000000000055511151231257827021181583404541015625).
  Raises xecConversion for NaN and infinity. }
function LandrixXmlDoubleToDecimal(const A: TLandrixXmlDouble): TLandrixXmlDecimal;
{ The cast to xs:integer: truncated towards zero. Raises xecConversion for
  NaN and infinity. Saxon truncates the decimal digits of Java's
  Double.toString instead of the exact value; below 2^53 that is the same.
  Above, this function uses the shortest round-trip digits (2^130 gives
  1361129467683754 followed by zeros), while Java 17, as bundled with the
  KoSIT validator, sometimes writes one digit more
  (13611294676837539...). }
function LandrixXmlDoubleToInteger(const A: TLandrixXmlDouble): TLandrixXmlDecimal;
{ The double nearest to A (ties to even), as for xs:double(decimal). }
function LandrixXmlDoubleFromDecimal(const A: TLandrixXmlDecimal): TLandrixXmlDouble;
function LandrixXmlDoubleFromInt64(Value: Int64): TLandrixXmlDouble;

{ IEEE 754 operations, rounded to nearest, ties to even. }
function LandrixXmlDoubleAdd(const A, B: TLandrixXmlDouble): TLandrixXmlDouble;
function LandrixXmlDoubleSubtract(const A, B: TLandrixXmlDouble): TLandrixXmlDouble;
function LandrixXmlDoubleMultiply(const A, B: TLandrixXmlDouble): TLandrixXmlDouble;
function LandrixXmlDoubleDivide(const A, B: TLandrixXmlDouble): TLandrixXmlDouble;
{ XPath "mod" (Java's %): A - B * trunc(A / B), exact; the sign follows A;
  NaN if A is infinite or B is zero. }
function LandrixXmlDoubleModulo(const A, B: TLandrixXmlDouble): TLandrixXmlDouble;
function LandrixXmlDoubleNegate(const A: TLandrixXmlDouble): TLandrixXmlDouble;
function LandrixXmlDoubleAbs(const A: TLandrixXmlDouble): TLandrixXmlDouble;

{ -1, 0 or 1; LandrixXmlDoubleUnordered if A or B is NaN. -0 equals +0. }
function LandrixXmlDoubleCompare(const A, B: TLandrixXmlDouble): Integer;

{ Rounds A to Precision fraction digits on its exact decimal value (see
  LandrixXmlDecimalRound for the modes). NaN, infinities and zeros are
  returned unchanged; a result of zero keeps the sign of A, so
  fn:round(-0.4e0) = -0 and fn:ceiling(-0.5e0) = -0. }
function LandrixXmlDoubleRound(const A: TLandrixXmlDouble; Precision: Integer;
  Mode: TLandrixXmlDecimalRounding): TLandrixXmlDouble;

{ xs:float has no type of its own: a float is a TLandrixXmlDouble whose
  value is a binary32 value. Float arithmetic is the double operation
  followed by LandrixXmlDoubleRoundToFloat; for + - * / that equals the
  binary32 operation, as a double holds more than twice the float
  precision. A native Single converts exactly through
  LandrixXmlDoubleFromNative and ...ToNative. }

{ The nearest binary32 value, ties to even: values from 2^128 on (after
  rounding) give +-INF, values below half of the smallest float subnormal
  give +-0; NaN, infinities and zeros are returned unchanged. }
function LandrixXmlDoubleRoundToFloat(const A: TLandrixXmlDouble): TLandrixXmlDouble;
{ True if A is a binary32 value (NaN, infinities and zeros included). }
function LandrixXmlDoubleIsFloat(const A: TLandrixXmlDouble): Boolean;
{ xs:float lexical form, the rules of LandrixXmlDoubleTryParse; the result
  is the binary32 value nearest to the number written, rounded once (not
  through the nearest double). }
function LandrixXmlDoubleTryParseFloat(const S: TLandrixXmlUtf8; out Value: TLandrixXmlDouble): Boolean;
{ Like LandrixXmlDoubleTryParseFloat, but raises ELandrixXmlError
  (xecConversion). }
function LandrixXmlDoubleParseFloat(const S: TLandrixXmlUtf8): TLandrixXmlDouble;
{ The binary32 value nearest to A, rounded once (xs:float(decimal)). }
function LandrixXmlDoubleFloatFromDecimal(const A: TLandrixXmlDecimal): TLandrixXmlDouble;
{ The XPath string value of the float nearest to A as Saxon HE 12 writes
  floats: the notation of LandrixXmlDoubleFormat, plain from the float
  nearest to 1E-6 to below 1E6; the digits of Saxon's algorithm at float
  precision; subnormal floats with Java's Float.toString digits (the
  closest of the shortest that read back, at least two: "1.4E-45"). }
function LandrixXmlDoubleFormatFloat(const A: TLandrixXmlDouble): TLandrixXmlUtf8;

implementation

const
  BigBits = 15;
  BigBase = 32768;
  BigMask = 32767;

  SignMask = Low(Int64); { bit 63; a hex literal above High(Int64) differs between compilers }
  FractionMask = Int64($000FFFFFFFFFFFFF);
  HiddenBit = Int64($0010000000000000);
  ExponentAll = 2047;
  BitsInfinity = Int64($7FF0000000000000);
  BitsNaN = Int64($7FF8000000000000);
  { 1E6 and 1E-6: limits of the plain notation }
  BitsMillion = Int64($412E848000000000);
  BitsMillionth = Int64($3EB0C6F7A0B5ED8D);
  BitsMaxDouble = Int64($7FEFFFFFFFFFFFFF);
  { 2^53: below, every double's integer part is exact in any decimal form }
  BitsTwoPow53 = Int64($4340000000000000);
  { the float nearest to 1E-6, the lower limit of the plain notation of
    floats, and 2^-126, the smallest normal float }
  BitsFloatMillionth = Int64($3EB0C6F7A0000000);
  BitsFloatMinNormal = Int64($3810000000000000);

type
  { Unsigned big integer, base 2^15, least significant limb first, no zero
    limb at the top; empty = 0. A product of two limbs plus carries stays
    below 2^31, also with overflow checks. Arrays are never written after
    the function that created them returns. }
  TBig = array of Integer;

procedure ShortestDigits(Bits: Int64; out Digits: AnsiString; out K: Integer); forward;

{ ---------------------------------------------------------------------- }
{ Bit patterns                                                           }
{ ---------------------------------------------------------------------- }

function BiasedExponent(Bits: Int64): Integer;
begin
  Result := Integer((Bits shr 52) and ExponentAll);
end;

function IsNaNBits(Bits: Int64): Boolean;
begin
  Result := (BiasedExponent(Bits) = ExponentAll) and ((Bits and FractionMask) <> 0);
end;

function Make(Bits: Int64): TLandrixXmlDouble;
begin
  Result.Bits := Bits;
end;

function LandrixXmlDoubleFromBits(Bits: Int64): TLandrixXmlDouble;
begin
  if IsNaNBits(Bits) then
    Result.Bits := BitsNaN
  else
    Result.Bits := Bits;
end;

function LandrixXmlDoubleFromNative(const Value: Double): TLandrixXmlDouble;
begin
  { a pointer cast reads the bytes without the FPU }
  Result := LandrixXmlDoubleFromBits(PInt64(@Value)^);
end;

function LandrixXmlDoubleToNative(const A: TLandrixXmlDouble): Double;
begin
  Result := PDouble(@A.Bits)^;
end;

function LandrixXmlDoubleNaN: TLandrixXmlDouble;
begin
  Result.Bits := BitsNaN;
end;

function LandrixXmlDoubleInfinity(Negative: Boolean): TLandrixXmlDouble;
begin
  if Negative then
    Result.Bits := BitsInfinity or SignMask
  else
    Result.Bits := BitsInfinity;
end;

function LandrixXmlDoubleZero(Negative: Boolean): TLandrixXmlDouble;
begin
  if Negative then
    Result.Bits := SignMask
  else
    Result.Bits := 0;
end;

function LandrixXmlDoubleIsNaN(const A: TLandrixXmlDouble): Boolean;
begin
  Result := IsNaNBits(A.Bits);
end;

function LandrixXmlDoubleIsInfinite(const A: TLandrixXmlDouble): Boolean;
begin
  Result := (A.Bits and not SignMask) = BitsInfinity;
end;

function LandrixXmlDoubleIsZero(const A: TLandrixXmlDouble): Boolean;
begin
  Result := (A.Bits and not SignMask) = 0;
end;

function LandrixXmlDoubleSignBit(const A: TLandrixXmlDouble): Boolean;
begin
  Result := (A.Bits < 0) and not IsNaNBits(A.Bits);
end;

function IsFiniteBits(Bits: Int64): Boolean;
begin
  Result := BiasedExponent(Bits) <> ExponentAll;
end;

{ Magnitude = Mantissa * 2^Exponent2 for a finite, non-zero bit pattern. }
procedure Decompose(Bits: Int64; out Mantissa: Int64; out Exponent2: Integer);
var
  Biased: Integer;
begin
  Biased := BiasedExponent(Bits);
  Mantissa := Bits and FractionMask;
  if Biased = 0 then
    Exponent2 := -1074
  else
  begin
    Mantissa := Mantissa or HiddenBit;
    Exponent2 := Biased - 1075;
  end;
end;

{ ---------------------------------------------------------------------- }
{ Big integers                                                           }
{ ---------------------------------------------------------------------- }

procedure BigTrim(var A: TBig);
var
  N: Integer;
begin
  N := Integer(Length(A));
  while (N > 0) and (A[N - 1] = 0) do
    Dec(N);
  if N <> Length(A) then
    SetLength(A, N);
end;

{ Value >= 0 }
function BigFromInt64(Value: Int64): TBig;
var
  N: Integer;
begin
  Result := nil;
  SetLength(Result, 5);
  N := 0;
  while Value > 0 do
  begin
    Result[N] := Integer(Value and BigMask);
    Value := Value shr BigBits;
    Inc(N);
  end;
  SetLength(Result, N);
end;

{ For values below 2^63. }
function BigToInt64(const A: TBig): Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := Integer(Length(A)) - 1 downto 0 do
    Result := (Result shl BigBits) or A[I];
end;

function BigBitLength(const A: TBig): Integer;
var
  Top: Integer;
begin
  Result := 0;
  if Length(A) = 0 then
    Exit;
  Result := (Integer(Length(A)) - 1) * BigBits;
  Top := A[Length(A) - 1];
  while Top > 0 do
  begin
    Inc(Result);
    Top := Top shr 1;
  end;
end;

function BigCompare(const A, B: TBig): Integer;
var
  I: Integer;
begin
  if Length(A) <> Length(B) then
  begin
    if Length(A) < Length(B) then
      Result := -1
    else
      Result := 1;
    Exit;
  end;
  for I := Integer(Length(A)) - 1 downto 0 do
    if A[I] <> B[I] then
    begin
      if A[I] < B[I] then
        Result := -1
      else
        Result := 1;
      Exit;
    end;
  Result := 0;
end;

function BigAdd(const A, B: TBig): TBig;
var
  I, N, T, Carry: Integer;
begin
  N := Integer(Length(A));
  if Length(B) > N then
    N := Integer(Length(B));
  Result := nil;
  SetLength(Result, N + 1);
  Carry := 0;
  for I := 0 to N - 1 do
  begin
    T := Carry;
    if I < Length(A) then
      Inc(T, A[I]);
    if I < Length(B) then
      Inc(T, B[I]);
    Result[I] := T and BigMask;
    Carry := T shr BigBits;
  end;
  Result[N] := Carry;
  BigTrim(Result);
end;

{ A - B, A >= B }
function BigSub(const A, B: TBig): TBig;
var
  I, T, Borrow: Integer;
begin
  Result := nil;
  SetLength(Result, Length(A));
  Borrow := 0;
  for I := 0 to Integer(Length(A)) - 1 do
  begin
    T := A[I] - Borrow;
    if I < Length(B) then
      Dec(T, B[I]);
    if T < 0 then
    begin
      Result[I] := T + BigBase;
      Borrow := 1;
    end
    else
    begin
      Result[I] := T;
      Borrow := 0;
    end;
  end;
  BigTrim(Result);
end;

{ A * M, 0 <= M <= 32768 }
function BigMulSmall(const A: TBig; M: Integer): TBig;
var
  I, T, Carry: Integer;
begin
  Result := nil;
  if (M = 0) or (Length(A) = 0) then
    Exit;
  SetLength(Result, Length(A) + 1);
  Carry := 0;
  for I := 0 to Integer(Length(A)) - 1 do
  begin
    T := A[I] * M + Carry;
    Result[I] := T and BigMask;
    Carry := T shr BigBits;
  end;
  Result[Length(A)] := Carry;
  BigTrim(Result);
end;

function BigMul(const A, B: TBig): TBig;
var
  I, J, T, Carry: Integer;
begin
  Result := nil;
  if (Length(A) = 0) or (Length(B) = 0) then
    Exit;
  SetLength(Result, Length(A) + Length(B));
  for I := 0 to Integer(Length(Result)) - 1 do
    Result[I] := 0;
  for I := 0 to Integer(Length(A)) - 1 do
  begin
    Carry := 0;
    for J := 0 to Integer(Length(B)) - 1 do
    begin
      T := Result[I + J] + A[I] * B[J] + Carry;
      Result[I + J] := T and BigMask;
      Carry := T shr BigBits;
    end;
    J := I + Integer(Length(B));
    while Carry <> 0 do
    begin
      T := Result[J] + Carry;
      Result[J] := T and BigMask;
      Carry := T shr BigBits;
      Inc(J);
    end;
  end;
  BigTrim(Result);
end;

{ A * 2^N, N >= 0 }
function BigShl(const A: TBig; N: Integer): TBig;
var
  Limbs, Bits, I, T, Carry: Integer;
begin
  Result := nil;
  if Length(A) = 0 then
    Exit;
  Limbs := N div BigBits;
  Bits := N mod BigBits;
  SetLength(Result, Integer(Length(A)) + Limbs + 1);
  for I := 0 to Limbs - 1 do
    Result[I] := 0;
  Carry := 0;
  for I := 0 to Integer(Length(A)) - 1 do
  begin
    T := (A[I] shl Bits) or Carry;
    Result[I + Limbs] := T and BigMask;
    Carry := T shr BigBits;
  end;
  Result[Integer(Length(A)) + Limbs] := Carry;
  BigTrim(Result);
end;

{ A div 2^N, N >= 0 }
function BigShr(const A: TBig; N: Integer): TBig;
var
  Limbs, Bits, I, T: Integer;
begin
  Result := nil;
  Limbs := N div BigBits;
  Bits := N mod BigBits;
  if Limbs >= Length(A) then
    Exit;
  SetLength(Result, Integer(Length(A)) - Limbs);
  for I := 0 to Integer(Length(Result)) - 1 do
  begin
    T := A[I + Limbs] shr Bits;
    if (Bits > 0) and (I + Limbs + 1 < Length(A)) then
      T := T or ((A[I + Limbs + 1] shl (BigBits - Bits)) and BigMask);
    Result[I] := T;
  end;
  BigTrim(Result);
end;

function BigTestBit(const A: TBig; N: Integer): Boolean;
begin
  Result := (N >= 0) and (N div BigBits < Length(A)) and
    (((A[N div BigBits] shr (N mod BigBits)) and 1) <> 0);
end;

{ True if any of the bits 0 .. N-1 is set. }
function BigAnyLowBit(const A: TBig; N: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  I := 0;
  while (N >= BigBits) and (I < Length(A)) do
  begin
    if A[I] <> 0 then
    begin
      Result := True;
      Exit;
    end;
    Inc(I);
    Dec(N, BigBits);
  end;
  if (N > 0) and (I < Length(A)) then
    Result := (A[I] and ((1 shl N) - 1)) <> 0;
end;

{ Quotient and remainder, B <> 0. }
procedure BigDivMod(const A, B: TBig; out Quotient, Remainder: TBig);
var
  I, Lo, Hi, Mid: Integer;
  Rest, Shifted: TBig;
begin
  Rest := nil;
  Shifted := nil;
  if BigCompare(A, B) < 0 then
  begin
    Quotient := nil;
    Remainder := A;
    Exit;
  end;
  SetLength(Quotient, Length(A));
  for I := Integer(Length(A)) - 1 downto 0 do
  begin
    { Rest := Rest * 2^15 + A[I] }
    Shifted := BigShl(Rest, BigBits);
    if A[I] <> 0 then
      Shifted := BigAdd(Shifted, BigFromInt64(A[I]));
    Rest := Shifted;
    { largest digit Q with B * Q <= Rest }
    Lo := 0;
    Hi := BigMask;
    while Lo < Hi do
    begin
      Mid := (Lo + Hi + 1) div 2;
      if BigCompare(BigMulSmall(B, Mid), Rest) <= 0 then
        Lo := Mid
      else
        Hi := Mid - 1;
    end;
    Quotient[I] := Lo;
    if Lo > 0 then
      Rest := BigSub(Rest, BigMulSmall(B, Lo));
  end;
  BigTrim(Quotient);
  Remainder := Rest;
end;

function BigPow10(K: Integer): TBig;
begin
  Result := BigFromInt64(1);
  while K >= 4 do
  begin
    Result := BigMulSmall(Result, 10000);
    Dec(K, 4);
  end;
  while K > 0 do
  begin
    Result := BigMulSmall(Result, 10);
    Dec(K);
  end;
end;

{ The coefficient of a decimal (base 10000 limbs) as a binary big integer. }
function BigFromDecimalLimbs(const Limbs: TLandrixXmlDecimalLimbs): TBig;
var
  I: Integer;
begin
  Result := nil;
  for I := Integer(Length(Limbs)) - 1 downto 0 do
  begin
    Result := BigMulSmall(Result, 10000);
    if Limbs[I] <> 0 then
      Result := BigAdd(Result, BigFromInt64(Limbs[I]));
  end;
end;

{ ---------------------------------------------------------------------- }
{ Rounding to binary64                                                   }
{ ---------------------------------------------------------------------- }

{ The double nearest to Q * 2^E2 (+ a non-zero rest below the last bit of
  Q if Sticky), ties to even; subnormal results and overflow to infinity
  included. With Float the nearest binary32 value instead, as a double. }
function PackRoundedTo(Negative: Boolean; const Q: TBig; E2: Integer; Sticky, Float: Boolean): Int64;
var
  L, X, P, Drop, Precision, MinExponent, MaxExponent: Integer;
  M: Int64;
  Guard, Rest: Boolean;
begin
  if Negative then
    Result := SignMask
  else
    Result := 0;
  L := BigBitLength(Q);
  if L = 0 then
    Exit;
  if Float then
  begin
    Precision := 24;
    MinExponent := -126;
    MaxExponent := 127;
  end
  else
  begin
    Precision := 53;
    MinExponent := -1022;
    MaxExponent := 1023;
  end;
  { leading bit at 2^X }
  X := L - 1 + E2;
  if X > MaxExponent then
  begin
    Result := Result or BitsInfinity;
    Exit;
  end;
  { significant bits to keep: Precision, fewer for subnormals }
  if X >= MinExponent then
    P := Precision
  else
    P := X - MinExponent + Precision;
  if P < 0 then
    Exit; { below half of the smallest subnormal }
  Drop := L - P;
  if Drop <= 0 then
    { exact; callers that pass Sticky scale Q to 55 or 56 bits, so Drop >= 2
      whenever Sticky is set and this branch never loses a rounding rest }
    M := BigToInt64(BigShl(Q, -Drop))
  else
  begin
    M := BigToInt64(BigShr(Q, Drop));
    Guard := BigTestBit(Q, Drop - 1);
    Rest := Sticky or BigAnyLowBit(Q, Drop - 1);
    if Guard and (Rest or ((M and 1) <> 0)) then
      Inc(M);
  end;
  if Float then
  begin
    { M * 2^(E2 + Drop) is a double; a carry may reach 2^(MaxExponent + 1) }
    if (X = MaxExponent) and (M = Int64(1) shl Precision) then
      Result := Result or BitsInfinity
    else
      Result := PackRoundedTo(Negative, BigFromInt64(M), E2 + Drop, False, False);
    Exit;
  end;
  if X >= -1022 then
  begin
    if M = 2 * HiddenBit then
    begin
      M := HiddenBit;
      Inc(X);
      if X > 1023 then
      begin
        Result := Result or BitsInfinity;
        Exit;
      end;
    end;
    Result := Result or ((Int64(X) + 1023) shl 52) or (M - HiddenBit);
  end
  else
    { subnormal; a carry into 2^52 gives the smallest normal number }
    Result := Result or M;
end;

function PackRounded(Negative: Boolean; const Q: TBig; E2: Integer; Sticky: Boolean): Int64;
begin
  Result := PackRoundedTo(Negative, Q, E2, Sticky, False);
end;

{ The double nearest to N * 10^E (N > 0 with DigitCount decimal digits),
  with Float the nearest binary32 value. }
function NearestDouble(Negative: Boolean; const N: TBig; DigitCount, E: Integer; Float: Boolean): Int64;
var
  Num, Den, Q, R: TBig;
  S: Integer;
begin
  Num := nil;
  Den := nil;
  { N * 10^E < 10^(DigitCount + E) }
  if DigitCount + E > 310 then
  begin
    Result := BitsInfinity;
    if Negative then
      Result := Result or SignMask;
    Exit;
  end;
  { below 10^-324, less than half of the smallest subnormal 4.94E-324 }
  if DigitCount + E < -324 then
  begin
    if Negative then
      Result := SignMask
    else
      Result := 0;
    Exit;
  end;
  if E >= 0 then
  begin
    Num := BigMul(N, BigPow10(E));
    Den := BigFromInt64(1);
  end
  else
  begin
    Num := N;
    Den := BigPow10(-E);
  end;
  { scale so that the quotient has 55 or 56 bits }
  S := 55 - (BigBitLength(Num) - BigBitLength(Den));
  if S >= 0 then
    Num := BigShl(Num, S)
  else
    Den := BigShl(Den, -S);
  BigDivMod(Num, Den, Q, R);
  Result := PackRoundedTo(Negative, Q, -S, Length(R) > 0, Float);
end;

{ ---------------------------------------------------------------------- }
{ Parsing                                                                }
{ ---------------------------------------------------------------------- }

function IsXmlSpace(C: AnsiChar): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13);
end;

function MatchesWord(const S: TLandrixXmlUtf8; First, Last: Integer; const Keyword: AnsiString): Boolean;
var
  I: Integer;
begin
  Result := Last - First + 1 = Length(Keyword);
  if Result then
    for I := 1 to Length(Keyword) do
      if AnsiChar(S[First + I - 1]) <> Keyword[I] then
      begin
        Result := False;
        Exit;
      end;
end;

const
  { Significant digits kept when reading a decimal number; more never
    change the nearest double (767 suffice for any binary64 halfway
    point), as long as a non-zero dropped digit is remembered. Keeps the
    big-integer work bounded for very long inputs. }
  MaxKeptDigits = 800;

function TryParseNumber(const S: TLandrixXmlUtf8; Float: Boolean; out Value: TLandrixXmlDouble): Boolean;
var
  First, Last, I, DigitCount, FracDigits, ExtraIntDigits, E, Chunk, ChunkLen, J: Integer;
  ExpValue, ExpLimit, E64: Int64;
  Negative, SeenPoint, ExpNegative, AnyDigit, AnyExpDigit, Dropped: Boolean;
  N: TBig;
  C: AnsiChar;
begin
  Result := False;
  Value.Bits := 0;
  N := nil;
  First := 1;
  Last := Length(S);
  while (First <= Last) and IsXmlSpace(AnsiChar(S[First])) do
    Inc(First);
  while (Last >= First) and IsXmlSpace(AnsiChar(S[Last])) do
    Dec(Last);
  if First > Last then
    Exit;
  if MatchesWord(S, First, Last, 'NaN') then
  begin
    Value.Bits := BitsNaN;
    Result := True;
    Exit;
  end;
  Negative := False;
  if (S[First] = '+') or (S[First] = '-') then
  begin
    Negative := S[First] = '-';
    Inc(First);
  end;
  if MatchesWord(S, First, Last, 'INF') then
  begin
    Value := LandrixXmlDoubleInfinity(Negative);
    Result := True;
    Exit;
  end;
  { mantissa; up to MaxKeptDigits significant digits go into N in chunks
    of four, later ones only count as integer digits or set Dropped }
  DigitCount := 0;
  FracDigits := 0;
  ExtraIntDigits := 0;
  Dropped := False;
  SeenPoint := False;
  AnyDigit := False;
  Chunk := 0;
  ChunkLen := 0;
  I := First;
  while I <= Last do
  begin
    C := AnsiChar(S[I]);
    if (C >= '0') and (C <= '9') then
    begin
      AnyDigit := True;
      if DigitCount >= MaxKeptDigits then
      begin
        if C <> '0' then
          Dropped := True;
        if not SeenPoint then
          Inc(ExtraIntDigits);
      end
      else
      begin
        if (DigitCount > 0) or (C <> '0') then
        begin
          Inc(DigitCount);
          Chunk := Chunk * 10 + (Ord(C) - Ord('0'));
          Inc(ChunkLen);
          if ChunkLen = 4 then
          begin
            N := BigMulSmall(N, 10000);
            if Chunk <> 0 then
              N := BigAdd(N, BigFromInt64(Chunk));
            Chunk := 0;
            ChunkLen := 0;
          end;
        end;
        if SeenPoint then
          Inc(FracDigits);
      end;
    end
    else if (C = '.') and not SeenPoint then
      SeenPoint := True
    else
      Break;
    Inc(I);
  end;
  if not AnyDigit then
    Exit;
  if ChunkLen > 0 then
  begin
    for J := 1 to ChunkLen do
      N := BigMulSmall(N, 10);
    if Chunk <> 0 then
      N := BigAdd(N, BigFromInt64(Chunk));
  end;
  { exponent; saturated at a limit beyond which it decides alone, whatever
    the number of digits: Length(S) + 400 }
  ExpValue := 0;
  ExpLimit := Int64(Length(S)) + 400;
  if I <= Last then
  begin
    C := AnsiChar(S[I]);
    if (C <> 'e') and (C <> 'E') then
      Exit;
    Inc(I);
    ExpNegative := False;
    if (I <= Last) and ((S[I] = '+') or (S[I] = '-')) then
    begin
      ExpNegative := S[I] = '-';
      Inc(I);
    end;
    AnyExpDigit := False;
    while I <= Last do
    begin
      C := AnsiChar(S[I]);
      if (C < '0') or (C > '9') then
        Exit;
      AnyExpDigit := True;
      if ExpValue < ExpLimit then
        ExpValue := ExpValue * 10 + (Int64(Ord(C)) - Ord('0'));
      Inc(I);
    end;
    if not AnyExpDigit then
      Exit;
    if ExpValue > ExpLimit then
      ExpValue := ExpLimit;
    if ExpNegative then
      ExpValue := -ExpValue;
  end;
  Result := True;
  if DigitCount = 0 then
  begin
    Value := LandrixXmlDoubleZero(Negative);
    Exit;
  end;
  { |E64| below 2^32; beyond +-10^8 only the sign matters for the range
    checks of NearestDouble (at most 801 digits are kept) }
  E64 := ExpValue + ExtraIntDigits - FracDigits;
  if E64 > 100000000 then
    E := 100000000
  else if E64 < -100000000 then
    E := -100000000
  else
    E := Integer(E64);
  if Dropped then
  begin
    { a final 1 stands for the non-zero rest of the dropped digits }
    N := BigAdd(BigMulSmall(N, 10), BigFromInt64(1));
    Inc(DigitCount);
    Dec(E);
  end;
  Value.Bits := NearestDouble(Negative, N, DigitCount, E, Float);
end;

function LandrixXmlDoubleTryParse(const S: TLandrixXmlUtf8; out Value: TLandrixXmlDouble): Boolean;
begin
  Result := TryParseNumber(S, False, Value);
end;

function LandrixXmlDoubleParse(const S: TLandrixXmlUtf8): TLandrixXmlDouble;
begin
  if not LandrixXmlDoubleTryParse(S, Result) then
    raise ELandrixXmlError.CreateCode(xecConversion, 'Invalid xs:double value "' +
      LandrixXmlEscapeForMessage(S, 40) + '"');
end;

function LandrixXmlDoubleTryParseFloat(const S: TLandrixXmlUtf8; out Value: TLandrixXmlDouble): Boolean;
begin
  Result := TryParseNumber(S, True, Value);
end;

function LandrixXmlDoubleParseFloat(const S: TLandrixXmlUtf8): TLandrixXmlDouble;
begin
  if not LandrixXmlDoubleTryParseFloat(S, Result) then
    raise ELandrixXmlError.CreateCode(xecConversion, 'Invalid xs:float value "' +
      LandrixXmlEscapeForMessage(S, 40) + '"');
end;

{ ---------------------------------------------------------------------- }
{ Conversions                                                            }
{ ---------------------------------------------------------------------- }

function DecimalDigitCount(const A: TLandrixXmlDecimal): Integer;
var
  Top: Integer;
begin
  Result := (Integer(Length(A.Limbs)) - 1) * 4;
  Top := A.Limbs[Length(A.Limbs) - 1];
  while Top > 0 do
  begin
    Inc(Result);
    Top := Top div 10;
  end;
end;

function FromDecimal(const A: TLandrixXmlDecimal; Float: Boolean): TLandrixXmlDouble;
var
  DigitCount, DropLimbs, I: Integer;
  Top: TLandrixXmlDecimalLimbs;
  N: TBig;
begin
  N := nil;
  Top := nil;
  if LandrixXmlDecimalIsZero(A) then
  begin
    Result.Bits := 0;
    Exit;
  end;
  DigitCount := DecimalDigitCount(A);
  if DigitCount <= MaxKeptDigits then
  begin
    Result.Bits := NearestDouble(A.Negative, BigFromDecimalLimbs(A.Limbs), DigitCount, A.Exponent, Float);
    Exit;
  end;
  { keep the top limbs (800 to 803 digits) and a final 1 for the rest,
    which is not zero: the lowest limb of a normalized coefficient never
    is; linear in the length, no division }
  DropLimbs := (DigitCount - MaxKeptDigits) div 4;
  SetLength(Top, Integer(Length(A.Limbs)) - DropLimbs);
  for I := 0 to Integer(Length(Top)) - 1 do
    Top[I] := A.Limbs[I + DropLimbs];
  N := BigFromDecimalLimbs(Top);
  DigitCount := DigitCount - 4 * DropLimbs;
  if DropLimbs > 0 then
  begin
    N := BigAdd(BigMulSmall(N, 10), BigFromInt64(1));
    Inc(DigitCount);
    Result.Bits := NearestDouble(A.Negative, N, DigitCount, A.Exponent + 4 * DropLimbs - 1, Float);
  end
  else
    Result.Bits := NearestDouble(A.Negative, N, DigitCount, A.Exponent, Float);
end;

function LandrixXmlDoubleFromDecimal(const A: TLandrixXmlDecimal): TLandrixXmlDouble;
begin
  Result := FromDecimal(A, False);
end;

function LandrixXmlDoubleFloatFromDecimal(const A: TLandrixXmlDecimal): TLandrixXmlDouble;
begin
  Result := FromDecimal(A, True);
end;

function LandrixXmlDoubleRoundToFloat(const A: TLandrixXmlDouble): TLandrixXmlDouble;
var
  Mantissa: Int64;
  E2: Integer;
begin
  if not IsFiniteBits(A.Bits) or ((A.Bits and not SignMask) = 0) then
  begin
    Result := LandrixXmlDoubleFromBits(A.Bits);
    Exit;
  end;
  Decompose(A.Bits, Mantissa, E2);
  Result.Bits := PackRoundedTo(A.Bits < 0, BigFromInt64(Mantissa), E2, False, True);
end;

function LandrixXmlDoubleIsFloat(const A: TLandrixXmlDouble): Boolean;
begin
  Result := LandrixXmlDoubleRoundToFloat(A).Bits = LandrixXmlDoubleFromBits(A.Bits).Bits;
end;

function LandrixXmlDoubleFromInt64(Value: Int64): TLandrixXmlDouble;
begin
  Result := LandrixXmlDoubleFromDecimal(LandrixXmlDecimalFromInt64(Value));
end;

function DecimalPower(Base: Integer; K: Integer): TLandrixXmlDecimal;
var
  Factor: TLandrixXmlDecimal;
begin
  Result := LandrixXmlDecimalFromInt64(1);
  Factor := LandrixXmlDecimalFromInt64(Base);
  while K > 0 do
  begin
    if (K and 1) <> 0 then
      Result := LandrixXmlDecimalMultiply(Result, Factor);
    K := K shr 1;
    if K > 0 then
      Factor := LandrixXmlDecimalMultiply(Factor, Factor);
  end;
end;

procedure RaiseNotFinite;
begin
  raise ELandrixXmlError.CreateCode(xecConversion,
    'NaN or infinity cannot be converted to xs:decimal or xs:integer');
end;

function LandrixXmlDoubleToDecimal(const A: TLandrixXmlDouble): TLandrixXmlDecimal;
var
  Mantissa: Int64;
  E2: Integer;
begin
  if not IsFiniteBits(A.Bits) then
    RaiseNotFinite;
  if (A.Bits and not SignMask) = 0 then
  begin
    Result := LandrixXmlDecimalZero;
    Exit;
  end;
  Decompose(A.Bits, Mantissa, E2);
  Result := LandrixXmlDecimalFromInt64(Mantissa);
  if E2 >= 0 then
    Result := LandrixXmlDecimalMultiply(Result, DecimalPower(2, E2))
  else
    { m * 2^-k = m * 5^k * 10^-k }
    Result := LandrixXmlDecimalMultiplyPow10(
      LandrixXmlDecimalMultiply(Result, DecimalPower(5, -E2)), E2);
  if A.Bits < 0 then
    Result := LandrixXmlDecimalNegate(Result);
end;

function LandrixXmlDoubleToInteger(const A: TLandrixXmlDouble): TLandrixXmlDecimal;
var
  Digits: AnsiString;
  K, I: Integer;
  Text: TLandrixXmlUtf8;
begin
  if (A.Bits and not SignMask) < BitsTwoPow53 then
    Result := LandrixXmlDecimalRound(LandrixXmlDoubleToDecimal(A), 0, xdrDown)
  else
  begin
    if not IsFiniteBits(A.Bits) then
      RaiseNotFinite;
    { an integer of K digits: Digits padded with zeros }
    ShortestDigits(A.Bits, Digits, K);
    Text := '';
    SetLength(Text, K);
    for I := 1 to K do
      if I <= Length(Digits) then
        Text[I] := Digits[I]
      else
        Text[I] := '0';
    Result := LandrixXmlParseDecimalInteger(Text);
    if A.Bits < 0 then
      Result := LandrixXmlDecimalNegate(Result);
  end;
end;

{ ---------------------------------------------------------------------- }
{ Arithmetic                                                             }
{ ---------------------------------------------------------------------- }

function LandrixXmlDoubleNegate(const A: TLandrixXmlDouble): TLandrixXmlDouble;
begin
  if IsNaNBits(A.Bits) then
    Result := A
  else
    Result.Bits := A.Bits xor SignMask;
end;

function LandrixXmlDoubleAbs(const A: TLandrixXmlDouble): TLandrixXmlDouble;
begin
  if IsNaNBits(A.Bits) then
    Result := A
  else
    Result.Bits := A.Bits and not SignMask;
end;

function LandrixXmlDoubleAdd(const A, B: TLandrixXmlDouble): TLandrixXmlDouble;
var
  MA, MB: Int64;
  EA, EB, E, C: Integer;
  QA, QB: TBig;
  NA, NB: Boolean;
begin
  QA := nil;
  QB := nil;
  if IsNaNBits(A.Bits) or IsNaNBits(B.Bits) then
  begin
    Result.Bits := BitsNaN;
    Exit;
  end;
  NA := A.Bits < 0;
  NB := B.Bits < 0;
  if LandrixXmlDoubleIsInfinite(A) or LandrixXmlDoubleIsInfinite(B) then
  begin
    if LandrixXmlDoubleIsInfinite(A) and LandrixXmlDoubleIsInfinite(B) and (NA <> NB) then
      Result.Bits := BitsNaN
    else if LandrixXmlDoubleIsInfinite(A) then
      Result := A
    else
      Result := B;
    Exit;
  end;
  if LandrixXmlDoubleIsZero(A) and LandrixXmlDoubleIsZero(B) then
  begin
    Result := LandrixXmlDoubleZero(NA and NB);
    Exit;
  end;
  if LandrixXmlDoubleIsZero(A) then
  begin
    Result := B;
    Exit;
  end;
  if LandrixXmlDoubleIsZero(B) then
  begin
    Result := A;
    Exit;
  end;
  Decompose(A.Bits, MA, EA);
  Decompose(B.Bits, MB, EB);
  if EA < EB then
    E := EA
  else
    E := EB;
  QA := BigShl(BigFromInt64(MA), EA - E);
  QB := BigShl(BigFromInt64(MB), EB - E);
  if NA = NB then
    Result.Bits := PackRounded(NA, BigAdd(QA, QB), E, False)
  else
  begin
    C := BigCompare(QA, QB);
    if C = 0 then
      Result.Bits := 0 { x + (-x) = +0 when rounding to nearest }
    else if C > 0 then
      Result.Bits := PackRounded(NA, BigSub(QA, QB), E, False)
    else
      Result.Bits := PackRounded(NB, BigSub(QB, QA), E, False);
  end;
end;

function LandrixXmlDoubleSubtract(const A, B: TLandrixXmlDouble): TLandrixXmlDouble;
begin
  Result := LandrixXmlDoubleAdd(A, LandrixXmlDoubleNegate(B));
end;

function LandrixXmlDoubleMultiply(const A, B: TLandrixXmlDouble): TLandrixXmlDouble;
var
  MA, MB: Int64;
  EA, EB: Integer;
  Negative: Boolean;
begin
  if IsNaNBits(A.Bits) or IsNaNBits(B.Bits) then
  begin
    Result.Bits := BitsNaN;
    Exit;
  end;
  Negative := (A.Bits < 0) <> (B.Bits < 0);
  if LandrixXmlDoubleIsInfinite(A) or LandrixXmlDoubleIsInfinite(B) then
  begin
    if LandrixXmlDoubleIsZero(A) or LandrixXmlDoubleIsZero(B) then
      Result.Bits := BitsNaN
    else
      Result := LandrixXmlDoubleInfinity(Negative);
    Exit;
  end;
  if LandrixXmlDoubleIsZero(A) or LandrixXmlDoubleIsZero(B) then
  begin
    Result := LandrixXmlDoubleZero(Negative);
    Exit;
  end;
  Decompose(A.Bits, MA, EA);
  Decompose(B.Bits, MB, EB);
  Result.Bits := PackRounded(Negative, BigMul(BigFromInt64(MA), BigFromInt64(MB)), EA + EB, False);
end;

function LandrixXmlDoubleDivide(const A, B: TLandrixXmlDouble): TLandrixXmlDouble;
var
  MA, MB: Int64;
  EA, EB, S: Integer;
  Negative: Boolean;
  Num, Q, R: TBig;
begin
  Num := nil;
  if IsNaNBits(A.Bits) or IsNaNBits(B.Bits) then
  begin
    Result.Bits := BitsNaN;
    Exit;
  end;
  Negative := (A.Bits < 0) <> (B.Bits < 0);
  if LandrixXmlDoubleIsInfinite(A) then
  begin
    if LandrixXmlDoubleIsInfinite(B) then
      Result.Bits := BitsNaN
    else
      Result := LandrixXmlDoubleInfinity(Negative);
    Exit;
  end;
  if LandrixXmlDoubleIsInfinite(B) then
  begin
    Result := LandrixXmlDoubleZero(Negative);
    Exit;
  end;
  if LandrixXmlDoubleIsZero(B) then
  begin
    if LandrixXmlDoubleIsZero(A) then
      Result.Bits := BitsNaN
    else
      Result := LandrixXmlDoubleInfinity(Negative);
    Exit;
  end;
  if LandrixXmlDoubleIsZero(A) then
  begin
    Result := LandrixXmlDoubleZero(Negative);
    Exit;
  end;
  Decompose(A.Bits, MA, EA);
  Decompose(B.Bits, MB, EB);
  { the quotient gets 55 or 56 bits; S is between 3 and 107 }
  S := 55 - (BigBitLength(BigFromInt64(MA)) - BigBitLength(BigFromInt64(MB)));
  Num := BigShl(BigFromInt64(MA), S);
  BigDivMod(Num, BigFromInt64(MB), Q, R);
  Result.Bits := PackRounded(Negative, Q, EA - EB - S, Length(R) > 0);
end;

function LandrixXmlDoubleModulo(const A, B: TLandrixXmlDouble): TLandrixXmlDouble;
var
  MA, MB: Int64;
  EA, EB, E: Integer;
  Q, R: TBig;
begin
  if IsNaNBits(A.Bits) or IsNaNBits(B.Bits) or LandrixXmlDoubleIsInfinite(A) or
    LandrixXmlDoubleIsZero(B) then
  begin
    Result.Bits := BitsNaN;
    Exit;
  end;
  if LandrixXmlDoubleIsInfinite(B) or LandrixXmlDoubleIsZero(A) then
  begin
    Result := A;
    Exit;
  end;
  Decompose(A.Bits, MA, EA);
  Decompose(B.Bits, MB, EB);
  if EA < EB then
    E := EA
  else
    E := EB;
  BigDivMod(BigShl(BigFromInt64(MA), EA - E), BigShl(BigFromInt64(MB), EB - E), Q, R);
  { the remainder is exact and keeps the sign of A, also when it is zero }
  Result.Bits := PackRounded(A.Bits < 0, R, E, False);
end;

function OrderKey(Bits: Int64): Int64;
begin
  { positive doubles order like their bit patterns; -0 maps to 0 }
  if Bits < 0 then
    Result := -(Bits and not SignMask)
  else
    Result := Bits;
end;

function LandrixXmlDoubleCompare(const A, B: TLandrixXmlDouble): Integer;
var
  KA, KB: Int64;
begin
  if IsNaNBits(A.Bits) or IsNaNBits(B.Bits) then
  begin
    Result := LandrixXmlDoubleUnordered;
    Exit;
  end;
  KA := OrderKey(A.Bits);
  KB := OrderKey(B.Bits);
  if KA < KB then
    Result := -1
  else if KA > KB then
    Result := 1
  else
    Result := 0;
end;

function LandrixXmlDoubleRound(const A: TLandrixXmlDouble; Precision: Integer;
  Mode: TLandrixXmlDecimalRounding): TLandrixXmlDouble;
var
  Mantissa: Int64;
  E2: Integer;
begin
  if not IsFiniteBits(A.Bits) or LandrixXmlDoubleIsZero(A) then
  begin
    Result := A;
    Exit;
  end;
  Decompose(A.Bits, Mantissa, E2);
  { already integral: nothing to round at Precision >= 0; a double never
    has more than 1074 fraction digits }
  if ((E2 >= 0) and (Precision >= 0)) or (Precision > 1100) then
  begin
    Result := A;
    Exit;
  end;
  { |A| < 10^309: rounding to 10^400 gives the same as to any coarser unit
    (zero, or +-INF for floor and ceiling away from zero) }
  if Precision < -400 then
    Precision := -400;
  Result := LandrixXmlDoubleFromDecimal(LandrixXmlDecimalRound(LandrixXmlDoubleToDecimal(A),
    Precision, Mode));
  if LandrixXmlDoubleIsZero(Result) then
    Result := LandrixXmlDoubleZero(A.Bits < 0);
end;

{ ---------------------------------------------------------------------- }
{ Shortest digits and the XPath string value                             }
{ ---------------------------------------------------------------------- }

{ Floor division for possibly negative numerators. }
function FloorDiv(A, B: Integer): Integer;
begin
  Result := A div B;
  if (A mod B <> 0) and ((A < 0) <> (B < 0)) then
    Dec(Result);
end;

{ Shortest digit string D and decimal exponent K with Value = 0.D * 10^K
  that reads back as Value (Burger and Dybvig's free-format algorithm;
  boundaries count as reading back for an even mantissa, as with round
  half to even). Bits must be finite and non-zero; the sign is ignored. }
procedure ShortestDigits(Bits: Int64; out Digits: AnsiString; out K: Integer);
var
  Mantissa: Int64;
  E2, X, D, C: Integer;
  R, S, MPlus, MMinus, Factor: TBig;
  Even, UnequalGap, Low, High: Boolean;
begin
  R := nil;
  S := nil;
  MPlus := nil;
  MMinus := nil;
  Factor := nil;
  Digits := '';
  Bits := Bits and not SignMask;
  Decompose(Bits, Mantissa, E2);
  Even := (Mantissa and 1) = 0;
  { at the bottom of a binade the gap to the lower neighbour is half as large }
  UnequalGap := ((Bits and FractionMask) = 0) and (BiasedExponent(Bits) > 1);
  if E2 >= 0 then
  begin
    if UnequalGap then
    begin
      R := BigShl(BigFromInt64(Mantissa), E2 + 2);
      S := BigFromInt64(4);
      MPlus := BigShl(BigFromInt64(1), E2 + 1);
    end
    else
    begin
      R := BigShl(BigFromInt64(Mantissa), E2 + 1);
      S := BigFromInt64(2);
      MPlus := BigShl(BigFromInt64(1), E2);
    end;
    MMinus := BigShl(BigFromInt64(1), E2);
  end
  else if UnequalGap then
  begin
    R := BigFromInt64(Mantissa * 4);
    S := BigShl(BigFromInt64(1), 2 - E2);
    MPlus := BigFromInt64(2);
    MMinus := BigFromInt64(1);
  end
  else
  begin
    R := BigFromInt64(Mantissa * 2);
    S := BigShl(BigFromInt64(1), 1 - E2);
    MPlus := BigFromInt64(1);
    MMinus := BigFromInt64(1);
  end;
  { start below the result: Value >= 2^X and 1233 / 4096 < log10(2) }
  X := E2 + BigBitLength(BigFromInt64(Mantissa)) - 1;
  K := FloorDiv(X * 1233, 4096) - 1;
  if K >= 0 then
    S := BigMul(S, BigPow10(K))
  else
  begin
    Factor := BigPow10(-K);
    R := BigMul(R, Factor);
    MPlus := BigMul(MPlus, Factor);
    MMinus := BigMul(MMinus, Factor);
  end;
  { smallest K with (R + M+) / S < 1 (<= 1 if the upper boundary reads back) }
  while True do
  begin
    C := BigCompare(BigAdd(R, MPlus), S);
    if (C > 0) or (Even and (C = 0)) then
    begin
      S := BigMulSmall(S, 10);
      Inc(K);
    end
    else
      Break;
  end;
  repeat
    R := BigMulSmall(R, 10);
    MPlus := BigMulSmall(MPlus, 10);
    MMinus := BigMulSmall(MMinus, 10);
    D := 0;
    while BigCompare(R, S) >= 0 do
    begin
      R := BigSub(R, S);
      Inc(D);
    end;
    if Even then
    begin
      Low := BigCompare(R, MMinus) <= 0;
      High := BigCompare(BigAdd(R, MPlus), S) >= 0;
    end
    else
    begin
      Low := BigCompare(R, MMinus) < 0;
      High := BigCompare(BigAdd(R, MPlus), S) > 0;
    end;
    if Low and High then
    begin
      { both candidates read back: the nearer one, ties to the even digit
        as in Python's repr }
      C := BigCompare(BigAdd(R, R), S);
      if (C > 0) or ((C = 0) and Odd(D)) then
        Inc(D);
    end
    else if High then
      Inc(D);
    Digits := Digits + AnsiChar(Ord('0') + D);
  until Low or High;
end;

{ The digits Saxon HE 12 writes for a normal double (its Steele and White
  free-format variant in FloatingPointConverter). It differs from the
  shortest round-trip digits of ShortestDigits in three ways, reproduced
  on purpose: the gap below and above the value is always taken as equal
  (also at the bottom of a binade, where the gap below is half as large;
  the output may then not read back), the decimal exponent is raised
  while the upper boundary is reached inclusively but digit generation
  treats both boundaries exclusively (1E23 becomes 0.9999999999999999E23),
  and a tie between two final digits takes the lower one. Same contract
  as ShortestDigits for the value Mantissa * 2^E2, a normal number of its
  precision (the gap is 2^E2: floats pass their 24-bit mantissa). }
procedure SaxonDigits(Mantissa: Int64; E2: Integer; out Digits: AnsiString; out K: Integer);
var
  D: Integer;
  R, S, M, R2: TBig;
  Low, High: Boolean;
begin
  R := nil;
  S := nil;
  M := nil;
  R2 := nil;
  Digits := '';
  if E2 >= 0 then
  begin
    R := BigShl(BigFromInt64(Mantissa), E2);
    S := BigFromInt64(1);
    M := BigShl(BigFromInt64(1), E2);
  end
  else
  begin
    R := BigFromInt64(Mantissa);
    S := BigShl(BigFromInt64(1), -E2);
    M := BigFromInt64(1);
  end;
  K := 0;
  { scale up while R < S / 10 }
  while BigCompare(BigMulSmall(R, 10), S) < 0 do
  begin
    Dec(K);
    R := BigMulSmall(R, 10);
    M := BigMulSmall(M, 10);
  end;
  { raise K while 2R + M >= 2S }
  while BigCompare(BigAdd(BigAdd(R, R), M), BigAdd(S, S)) >= 0 do
  begin
    S := BigMulSmall(S, 10);
    Inc(K);
  end;
  repeat
    R := BigMulSmall(R, 10);
    M := BigMulSmall(M, 10);
    D := 0;
    while BigCompare(R, S) >= 0 do
    begin
      R := BigSub(R, S);
      Inc(D);
    end;
    R2 := BigAdd(R, R);
    Low := BigCompare(R2, M) < 0;
    High := BigCompare(BigAdd(R2, M), BigAdd(S, S)) > 0;
    if High and (not Low or (BigCompare(R2, S) > 0)) then
      Inc(D);
    Digits := Digits + AnsiChar(Ord('0') + D);
  until Low or High;
end;

function Zeros(Count: Integer): AnsiString;
var
  I: Integer;
begin
  Result := '';
  SetLength(Result, Count);
  for I := 1 to Count do
    Result[I] := '0';
end;

function IntToAnsi(Value: Integer): AnsiString;
var
  Negative: Boolean;
begin
  Result := '';
  Negative := Value < 0;
  if Negative then
    Value := -Value;
  repeat
    Result := AnsiChar(Ord('0') + Value mod 10) + Result;
    Value := Value div 10;
  until Value = 0;
  if Negative then
    Result := '-' + Result;
end;

{ Java's Float.toString digits for a subnormal float A > 0 (as
  ShortestDigits, but the closest of the shortest that read back and at
  least two): the exact value rounded to 2, 3, ... digits, half to even,
  until it reads back. }
procedure JavaFloatDigits(const A: TLandrixXmlDouble; out Digits: AnsiString; out K: Integer);
var
  Exact: TLandrixXmlUtf8;
  All, Candidate, Text: AnsiString;
  I, P, CK: Integer;
  Up: Boolean;
  Back: TLandrixXmlDouble;
begin
  { the exact value is 0.000...ddd: K counts the zeros after the point }
  Exact := LandrixXmlFormatDecimal(LandrixXmlDoubleToDecimal(A));
  I := 3;
  K := 0;
  while Exact[I] = '0' do
  begin
    Inc(I);
    Dec(K);
  end;
  All := '';
  SetLength(All, Length(Exact) - I + 1);
  Move(Exact[I], PAnsiChar(All)^, Length(All));
  CK := K;
  P := 2;
  while True do
  begin
    CK := K;
    if Length(All) <= P then
      Candidate := All
    else
    begin
      Candidate := Copy(All, 1, P);
      Up := All[P + 1] > '5';
      if All[P + 1] = '5' then
      begin
        { the exact digits end without zeros, so a 5 followed by more is above the tie }
        Up := (Length(All) > P + 1) or Odd(Ord(Candidate[P]));
      end;
      if Up then
      begin
        I := P;
        while (I >= 1) and (Candidate[I] = '9') do
        begin
          Candidate[I] := '0';
          Dec(I);
        end;
        if I >= 1 then
          Candidate[I] := AnsiChar(Ord(Candidate[I]) + 1)
        else
        begin
          Candidate := '1' + Copy(Candidate, 1, P - 1);
          Inc(CK);
        end;
      end;
    end;
    Text := '0.' + Candidate + 'E' + IntToAnsi(CK);
    { byte copy: a string cast would convert code pages on Delphi 2009+ }
    Exact := '';
    SetLength(Exact, Length(Text));
    Move(PAnsiChar(Text)^, PAnsiChar(Exact)^, Length(Text));
    if LandrixXmlDoubleTryParseFloat(Exact, Back) and (Back.Bits = A.Bits) then
      Break;
    Inc(P);
  end;
  while (Length(Candidate) > 1) and (Candidate[Length(Candidate)] = '0') do
    SetLength(Candidate, Length(Candidate) - 1);
  Digits := Candidate;
  K := CK;
end;

{ The XPath string value of A, a double or (Float) a float. }
function FormatNumber(const A: TLandrixXmlDouble; Float: Boolean): TLandrixXmlUtf8;
var
  Magnitude, Mantissa, Lower: Int64;
  Digits, Text: AnsiString;
  K, E2: Integer;
begin
  Magnitude := A.Bits and not SignMask;
  if Float then
    Lower := BitsFloatMillionth
  else
    Lower := BitsMillionth;
  if not IsFiniteBits(A.Bits) then
  begin
    if Magnitude <> BitsInfinity then
      Text := 'NaN'
    else if A.Bits < 0 then
      Text := '-INF'
    else
      Text := 'INF';
  end
  else if Magnitude = 0 then
  begin
    if A.Bits < 0 then
      Text := '-0'
    else
      Text := '0';
  end
  else if (Magnitude = BitsMaxDouble) and not Float then
  begin
    { written literally by Saxon }
    if A.Bits < 0 then
      Text := '-1.7976931348623157E308'
    else
      Text := '1.7976931348623157E308';
  end
  else
  begin
    { Saxon writes subnormal numbers with Java's Double.toString, which
      gives the shortest digits for them (4.9E-324 for the smallest is a
      literal in Saxon as well) }
    if Float then
    begin
      if Magnitude < BitsFloatMinNormal then
        JavaFloatDigits(Make(Magnitude), Digits, K)
      else
      begin
        { the 24-bit mantissa of a normal float }
        Decompose(Magnitude, Mantissa, E2);
        SaxonDigits(Mantissa shr 29, E2 + 29, Digits, K);
      end;
    end
    else if Magnitude = 1 then
    begin
      Digits := '49';
      K := -323;
    end
    else if BiasedExponent(A.Bits) = 0 then
      ShortestDigits(A.Bits, Digits, K)
    else
    begin
      Decompose(Magnitude, Mantissa, E2);
      SaxonDigits(Mantissa, E2, Digits, K);
    end;
    if (Magnitude >= Lower) and (Magnitude < BitsMillion) then
    begin
      if K <= 0 then
        Text := '0.' + Zeros(-K) + Digits
      else if K >= Length(Digits) then
        Text := Digits + Zeros(K - Length(Digits))
      else
        Text := Copy(Digits, 1, K) + '.' + Copy(Digits, K + 1, MaxInt);
    end
    else
    begin
      Text := Copy(Digits, 1, 1) + '.';
      if Length(Digits) > 1 then
        Text := Text + Copy(Digits, 2, MaxInt)
      else
        Text := Text + '0';
      Text := Text + 'E' + IntToAnsi(K - 1);
    end;
    if A.Bits < 0 then
      Text := '-' + Text;
  end;
  { byte copy: a string cast would convert code pages on Delphi 2009+ }
  Result := '';
  SetLength(Result, Length(Text));
  Move(PAnsiChar(Text)^, PAnsiChar(Result)^, Length(Text));
end;

function LandrixXmlDoubleFormat(const A: TLandrixXmlDouble): TLandrixXmlUtf8;
begin
  Result := FormatNumber(A, False);
end;

function LandrixXmlDoubleFormatFloat(const A: TLandrixXmlDouble): TLandrixXmlUtf8;
begin
  Result := FormatNumber(LandrixXmlDoubleRoundToFloat(A), True);
end;

end.
