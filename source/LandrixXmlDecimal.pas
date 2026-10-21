{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Exact decimal arithmetic for xs:decimal and xs:integer (part of the
  optional validation units; the core units do not use it).

  A value is Coefficient * 10^Exponent with an arbitrary-precision
  coefficient. Values are always normalized: the coefficient has no
  trailing decimal zero (2000 is stored as 2 * 10^3), and zero is stored as
  an empty coefficient with Exponent 0 and Negative = False. This matches
  Saxon, which keeps xs:decimal values stripped of trailing zeros; the
  scale (= -Exponent) of a normalized value therefore equals Saxon's scale
  and decides the precision of a division (see LandrixXmlDecimalDivide).

  The record fields are public only because Delphi 6 records cannot hide
  them. Treat them as read-only and build values with the functions below:
  the limb array of a value may be shared with other values, so writing
  into it would change them as well.

  Errors raise ELandrixXmlError: xecConversion for invalid lexical forms,
  xecArithmetic for division by zero and for exponents beyond
  +-LandrixXmlDecimalMaxExponent. }

unit LandrixXmlDecimal;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  LandrixXmlBase;

const
  { Largest absolute decimal exponent of a result. Protects against
    runaway values (e.g. repeated multiplication in a loop); far beyond
    anything a business document needs. }
  LandrixXmlDecimalMaxExponent = 1000000;

  { Minimum number of fraction digits of a decimal division (Saxon's
    DIVIDE_PRECISION). }
  LandrixXmlDecimalDividePrecision = 18;

type
  { Coefficient limbs, base 10000, least significant limb first, no zero
    limb at the top; empty = 0. }
  TLandrixXmlDecimalLimbs = array of Integer;

  TLandrixXmlDecimal = record
    Negative: Boolean;
    Exponent: Integer;
    Limbs: TLandrixXmlDecimalLimbs;
  end;

  { Rounding of a result to a given number of fraction digits. }
  TLandrixXmlDecimalRounding = (
    xdrFloor,       { towards negative infinity (fn:floor) }
    xdrCeiling,     { towards positive infinity (fn:ceiling) }
    xdrDown,        { towards zero (truncation, cast to xs:integer, idiv) }
    xdrHalfCeiling, { nearest, ties towards positive infinity (fn:round) }
    xdrHalfEven,    { nearest, ties to the even neighbour (fn:round-half-to-even) }
    xdrHalfDown     { nearest, ties towards zero (Saxon's decimal division) }
  );

function LandrixXmlDecimalZero: TLandrixXmlDecimal;
function LandrixXmlDecimalFromInt64(Value: Int64): TLandrixXmlDecimal;

{ Lexical forms. Leading and trailing XML white space (space, TAB, CR, LF)
  is ignored, as for the whiteSpace facet "collapse" of xs:decimal.
  xs:decimal: optional sign, digits with an optional '.', at least one
  digit ("1", "-1.50", "+.5", "5."). No exponent.
  xs:integer: optional sign and at least one digit. }
function LandrixXmlTryParseDecimal(const S: TLandrixXmlUtf8;
  out Value: TLandrixXmlDecimal): Boolean;
function LandrixXmlTryParseDecimalInteger(const S: TLandrixXmlUtf8;
  out Value: TLandrixXmlDecimal): Boolean;
{ Like the Try variants, but raise ELandrixXmlError (xecConversion). }
function LandrixXmlParseDecimal(const S: TLandrixXmlUtf8): TLandrixXmlDecimal;
function LandrixXmlParseDecimalInteger(const S: TLandrixXmlUtf8): TLandrixXmlDecimal;

{ The XPath string value: an integral value without decimal point ("12",
  "-3"), otherwise the shortest exact form ("0.5", "-12.25"). }
function LandrixXmlFormatDecimal(const A: TLandrixXmlDecimal): TLandrixXmlUtf8;

{ True and Value set if A is integral and fits into Int64. }
function LandrixXmlDecimalTryToInt64(const A: TLandrixXmlDecimal;
  out Value: Int64): Boolean;

function LandrixXmlDecimalIsZero(const A: TLandrixXmlDecimal): Boolean;
function LandrixXmlDecimalIsInteger(const A: TLandrixXmlDecimal): Boolean;
{ -1, 0 or 1. }
function LandrixXmlDecimalSign(const A: TLandrixXmlDecimal): Integer;
{ Number of fraction digits of the normalized value; negative for an
  integral value with trailing zeros (2000 -> -3). Saxon's scale. }
function LandrixXmlDecimalScale(const A: TLandrixXmlDecimal): Integer;
{ -1 if A < B, 0 if equal, 1 if A > B. }
function LandrixXmlDecimalCompare(const A, B: TLandrixXmlDecimal): Integer;

function LandrixXmlDecimalNegate(const A: TLandrixXmlDecimal): TLandrixXmlDecimal;
function LandrixXmlDecimalAbs(const A: TLandrixXmlDecimal): TLandrixXmlDecimal;
function LandrixXmlDecimalAdd(const A, B: TLandrixXmlDecimal): TLandrixXmlDecimal;
function LandrixXmlDecimalSubtract(const A, B: TLandrixXmlDecimal): TLandrixXmlDecimal;
function LandrixXmlDecimalMultiply(const A, B: TLandrixXmlDecimal): TLandrixXmlDecimal;

{ Decimal division as Saxon performs "div" on two xs:decimal values: the
  quotient is rounded half down (ties towards zero) to
  max(18, ScaleA - ScaleB + 18) fraction digits, where ScaleA and ScaleB
  are the operands' scales (LandrixXmlDecimalScale). }
function LandrixXmlDecimalDivide(const A, B: TLandrixXmlDecimal): TLandrixXmlDecimal;
{ The same with explicit operand scales. Saxon uses scale 0 for an
  xs:integer operand of a decimal division (e.g. "1.5 div 2000"), not its
  normalized scale. }
function LandrixXmlDecimalDivideScaled(const A, B: TLandrixXmlDecimal;
  ScaleA, ScaleB: Integer): TLandrixXmlDecimal;
{ "div" (not "idiv", see LandrixXmlDecimalIntegerQuotient) on two
  xs:integer values as Saxon performs it: if both operands are
  in 0..2^31-1 and the division is exact, the result is the integer
  quotient (IsInteger = True); otherwise a decimal division, with operand
  scales 0 if both are in 0..2^31-1 and normalized scales else (so
  1 div 2000000000000000000 gives 0.0000000000000000005). IsInteger tells
  whether the result is an xs:integer or an xs:decimal value, which matters
  for later divisions. Raises xecInvalidArgument if an operand is not
  integral. }
function LandrixXmlDecimalDivideIntegers(const A, B: TLandrixXmlDecimal;
  out IsInteger: Boolean): TLandrixXmlDecimal;
{ XPath "idiv": the quotient truncated towards zero (an integer). Not to be
  confused with LandrixXmlDecimalDivideIntegers, which is "div" on two
  xs:integer values. }
function LandrixXmlDecimalIntegerQuotient(const A, B: TLandrixXmlDecimal): TLandrixXmlDecimal;
{ XPath "mod": A - B * (A idiv B); the sign follows A. }
function LandrixXmlDecimalModulo(const A, B: TLandrixXmlDecimal): TLandrixXmlDecimal;

{ Rounds A to Precision fraction digits (negative: to tens, hundreds, ...).
  fn:round(A) = Round(A, 0, xdrHalfCeiling); fn:floor, fn:ceiling and the
  cast to xs:integer use Precision 0 with xdrFloor, xdrCeiling, xdrDown. }
function LandrixXmlDecimalRound(const A: TLandrixXmlDecimal; Precision: Integer;
  Mode: TLandrixXmlDecimalRounding): TLandrixXmlDecimal;

{ XML Schema facets: the number of digits counted by totalDigits and
  fractionDigits (as Xerces counts them: integer digits without leading
  zeros plus fraction digits without trailing zeros; 0 for zero). }
function LandrixXmlDecimalTotalDigits(const A: TLandrixXmlDecimal): Integer;
function LandrixXmlDecimalFractionDigits(const A: TLandrixXmlDecimal): Integer;

implementation

const
  LimbBase = 10000;
  LimbDigits = 4;
  Pow10Small: array[0..LimbDigits] of Integer = (1, 10, 100, 1000, 10000);

{ ---------------------------------------------------------------------- }
{ Unsigned coefficients (natural numbers in base 10000)                  }
{ ---------------------------------------------------------------------- }

procedure NatTrim(var A: TLandrixXmlDecimalLimbs);
var
  N: Integer;
begin
  N := Integer(Length(A));
  while (N > 0) and (A[N - 1] = 0) do
    Dec(N);
  if N <> Length(A) then
    SetLength(A, N);
end;

function NatFromInteger(Value: Integer): TLandrixXmlDecimalLimbs;
var
  N: Integer;
begin
  Result := nil;
  SetLength(Result, 3);
  N := 0;
  while Value > 0 do
  begin
    Result[N] := Value mod LimbBase;
    Value := Value div LimbBase;
    Inc(N);
  end;
  SetLength(Result, N);
end;

function NatCompare(const A, B: TLandrixXmlDecimalLimbs): Integer;
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

function NatAdd(const A, B: TLandrixXmlDecimalLimbs): TLandrixXmlDecimalLimbs;
var
  I, N, Carry, T: Integer;
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
    if T >= LimbBase then
    begin
      Result[I] := T - LimbBase;
      Carry := 1;
    end
    else
    begin
      Result[I] := T;
      Carry := 0;
    end;
  end;
  Result[N] := Carry;
  NatTrim(Result);
end;

{ A - B; requires A >= B. }
function NatSub(const A, B: TLandrixXmlDecimalLimbs): TLandrixXmlDecimalLimbs;
var
  I, Borrow, T: Integer;
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
      Result[I] := T + LimbBase;
      Borrow := 1;
    end
    else
    begin
      Result[I] := T;
      Borrow := 0;
    end;
  end;
  NatTrim(Result);
end;

{ A * M with 0 <= M <= 10000. }
function NatMulSmall(const A: TLandrixXmlDecimalLimbs; M: Integer): TLandrixXmlDecimalLimbs;
var
  I, Carry, T: Integer;
begin
  if (M = 0) or (Length(A) = 0) then
  begin
    Result := nil;
    Exit;
  end;
  SetLength(Result, Length(A) + 1);
  Carry := 0;
  for I := 0 to Integer(Length(A)) - 1 do
  begin
    T := A[I] * M + Carry;
    Result[I] := T mod LimbBase;
    Carry := T div LimbBase;
  end;
  Result[Length(A)] := Carry;
  NatTrim(Result);
end;

function NatMul(const A, B: TLandrixXmlDecimalLimbs): TLandrixXmlDecimalLimbs;
var
  I, J, Carry, T: Integer;
begin
  if (Length(A) = 0) or (Length(B) = 0) then
  begin
    Result := nil;
    Exit;
  end;
  SetLength(Result, Length(A) + Length(B));
  for I := 0 to Integer(Length(Result)) - 1 do
    Result[I] := 0;
  for I := 0 to Integer(Length(A)) - 1 do
  begin
    Carry := 0;
    for J := 0 to Integer(Length(B)) - 1 do
    begin
      { at most 9999 + 9999 * 9999 + 9999 < 2^31 }
      T := Result[I + J] + A[I] * B[J] + Carry;
      Result[I + J] := T mod LimbBase;
      Carry := T div LimbBase;
    end;
    J := I + Integer(Length(B));
    while Carry <> 0 do
    begin
      T := Result[J] + Carry;
      Result[J] := T mod LimbBase;
      Carry := T div LimbBase;
      Inc(J);
    end;
  end;
  NatTrim(Result);
end;

{ A * 10000^N. }
function NatShiftLimbs(const A: TLandrixXmlDecimalLimbs; N: Integer): TLandrixXmlDecimalLimbs;
var
  I: Integer;
begin
  if (Length(A) = 0) or (N = 0) then
  begin
    Result := A;
    Exit;
  end;
  SetLength(Result, Length(A) + N);
  for I := 0 to N - 1 do
    Result[I] := 0;
  for I := 0 to Integer(Length(A)) - 1 do
    Result[I + N] := A[I];
end;

{ A * 10^K with K >= 0. }
function NatMulPow10(const A: TLandrixXmlDecimalLimbs; K: Integer): TLandrixXmlDecimalLimbs;
begin
  Result := NatShiftLimbs(A, K div LimbDigits);
  if K mod LimbDigits <> 0 then
    Result := NatMulSmall(Result, Pow10Small[K mod LimbDigits]);
end;

function NatPow10(K: Integer): TLandrixXmlDecimalLimbs;
begin
  Result := NatMulPow10(NatFromInteger(1), K);
end;

{ A div D and A mod D for 1 <= D <= 10000. }
function NatDivSmall(const A: TLandrixXmlDecimalLimbs; D: Integer;
  out Remainder: Integer): TLandrixXmlDecimalLimbs;
var
  I, T: Integer;
begin
  Result := nil;
  SetLength(Result, Length(A));
  Remainder := 0;
  for I := Integer(Length(A)) - 1 downto 0 do
  begin
    T := Remainder * LimbBase + A[I];
    Result[I] := T div D;
    Remainder := T mod D;
  end;
  NatTrim(Result);
end;

{ Quotient and remainder; B must not be zero. }
procedure NatDivMod(const A, B: TLandrixXmlDecimalLimbs;
  out Quotient, Remainder: TLandrixXmlDecimalLimbs);
var
  I, Lo, Hi, Mid, R: Integer;
  Rest, Shifted: TLandrixXmlDecimalLimbs;
begin
  { Delphi 6 warns about managed locals that an early Exit skips }
  Rest := nil;
  Shifted := nil;
  if NatCompare(A, B) < 0 then
  begin
    Quotient := nil;
    Remainder := A;
    Exit;
  end;
  if Length(B) = 1 then
  begin
    Quotient := NatDivSmall(A, B[0], R);
    Remainder := NatFromInteger(R);
    Exit;
  end;
  SetLength(Quotient, Length(A));
  for I := Integer(Length(A)) - 1 downto 0 do
  begin
    { Rest := Rest * 10000 + A[I] }
    if Length(Rest) = 0 then
    begin
      if A[I] <> 0 then
        Rest := NatFromInteger(A[I]);
    end
    else
    begin
      Shifted := NatShiftLimbs(Rest, 1);
      Shifted[0] := A[I]; { a fresh array: NatShiftLimbs copies for N > 0 }
      Rest := Shifted;
    end;
    { largest digit Q with B * Q <= Rest }
    Lo := 0;
    Hi := LimbBase - 1;
    while Lo < Hi do
    begin
      Mid := (Lo + Hi + 1) div 2;
      if NatCompare(NatMulSmall(B, Mid), Rest) <= 0 then
        Lo := Mid
      else
        Hi := Mid - 1;
    end;
    Quotient[I] := Lo;
    if Lo > 0 then
      Rest := NatSub(Rest, NatMulSmall(B, Lo));
  end;
  NatTrim(Quotient);
  Remainder := Rest;
end;

function NatDigitCount(const A: TLandrixXmlDecimalLimbs): Integer;
var
  Top: Integer;
begin
  if Length(A) = 0 then
  begin
    Result := 0;
    Exit;
  end;
  Result := (Integer(Length(A)) - 1) * LimbDigits;
  Top := A[Length(A) - 1];
  while Top > 0 do
  begin
    Inc(Result);
    Top := Top div 10;
  end;
end;

function NatTrailingZeroDigits(const A: TLandrixXmlDecimalLimbs): Integer;
var
  I, L: Integer;
begin
  Result := 0;
  I := 0;
  while (I < Length(A)) and (A[I] = 0) do
  begin
    Inc(Result, LimbDigits);
    Inc(I);
  end;
  if I < Length(A) then
  begin
    L := A[I];
    while L mod 10 = 0 do
    begin
      Inc(Result);
      L := L div 10;
    end;
  end;
end;

{ A div 10^K where A is known to be divisible. }
function NatDivPow10Exact(const A: TLandrixXmlDecimalLimbs; K: Integer): TLandrixXmlDecimalLimbs;
var
  I, N, R: Integer;
  Shifted: TLandrixXmlDecimalLimbs;
begin
  N := K div LimbDigits;
  Shifted := nil;
  SetLength(Shifted, Length(A) - N);
  for I := 0 to Integer(Length(Shifted)) - 1 do
    Shifted[I] := A[I + N];
  if K mod LimbDigits <> 0 then
    Result := NatDivSmall(Shifted, Pow10Small[K mod LimbDigits], R)
  else
    Result := Shifted;
end;

function NatIsOdd(const A: TLandrixXmlDecimalLimbs): Boolean;
begin
  Result := (Length(A) > 0) and (A[0] mod 2 = 1);
end;

{ Digits as ASCII text, '0' for zero. }
function NatToDigits(const A: TLandrixXmlDecimalLimbs): AnsiString;
var
  I, J, L, P: Integer;
begin
  if Length(A) = 0 then
  begin
    Result := '0';
    Exit;
  end;
  SetLength(Result, NatDigitCount(A));
  P := Length(Result);
  for I := 0 to Integer(Length(A)) - 1 do
  begin
    L := A[I];
    for J := 1 to LimbDigits do
    begin
      if P < 1 then
        Break;
      Result[P] := AnsiChar(Ord('0') + L mod 10);
      L := L div 10;
      Dec(P);
    end;
  end;
end;

{ ---------------------------------------------------------------------- }
{ Signed values                                                          }
{ ---------------------------------------------------------------------- }

procedure RaiseArithmetic(const Msg: string);
begin
  raise ELandrixXmlError.CreateCode(xecArithmetic, Msg);
end;

{ Builds a normalized value. Limbs must be trimmed. }
function MakeDecimal(Negative: Boolean; Exponent: Integer;
  const Limbs: TLandrixXmlDecimalLimbs): TLandrixXmlDecimal;
var
  Zeros: Integer;
begin
  if Length(Limbs) = 0 then
  begin
    Result.Negative := False;
    Result.Exponent := 0;
    Result.Limbs := nil;
    Exit;
  end;
  Zeros := NatTrailingZeroDigits(Limbs);
  if Zeros > 0 then
    Result.Limbs := NatDivPow10Exact(Limbs, Zeros)
  else
    Result.Limbs := Limbs;
  Result.Negative := Negative;
  Result.Exponent := Exponent + Zeros;
  if (Result.Exponent > LandrixXmlDecimalMaxExponent) or
    (Result.Exponent < -LandrixXmlDecimalMaxExponent) then
    RaiseArithmetic('Decimal exponent out of range');
end;

function LandrixXmlDecimalZero: TLandrixXmlDecimal;
begin
  Result := MakeDecimal(False, 0, nil);
end;

function LandrixXmlDecimalFromInt64(Value: Int64): TLandrixXmlDecimal;
var
  Limbs: TLandrixXmlDecimalLimbs;
  N: Integer;
  Negative: Boolean;
  R: Int64;
begin
  { works on the (possibly negative) value directly, so Low(Int64) needs
    no negation }
  Negative := Value < 0;
  Limbs := nil;
  SetLength(Limbs, 5);
  N := 0;
  while Value <> 0 do
  begin
    R := Value mod LimbBase;
    if R < 0 then
      R := -R;
    Limbs[N] := Integer(R);
    Value := Value div LimbBase;
    Inc(N);
  end;
  SetLength(Limbs, N);
  Result := MakeDecimal(Negative, 0, Limbs);
end;

function IsXmlSpace(C: AnsiChar): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13);
end;

{ Shared parser; AllowPoint = False for xs:integer. }
function TryParseCore(const S: TLandrixXmlUtf8; AllowPoint: Boolean;
  out Value: TLandrixXmlDecimal): Boolean;
var
  First, Last, I, FracDigits, DigitCount, K, ChunkEnd, ChunkStart, L, J: Integer;
  Negative, SeenPoint: Boolean;
  Digits: AnsiString;
  Limbs: TLandrixXmlDecimalLimbs;
  C: AnsiChar;
begin
  Result := False;
  Value := LandrixXmlDecimalZero;
  First := 1;
  Last := Length(S);
  while (First <= Last) and IsXmlSpace(AnsiChar(S[First])) do
    Inc(First);
  while (Last >= First) and IsXmlSpace(AnsiChar(S[Last])) do
    Dec(Last);
  if First > Last then
    Exit;
  Negative := False;
  if (S[First] = '+') or (S[First] = '-') then
  begin
    Negative := S[First] = '-';
    Inc(First);
  end;
  Digits := '';
  SetLength(Digits, Last - First + 1);
  DigitCount := 0;
  FracDigits := 0;
  SeenPoint := False;
  for I := First to Last do
  begin
    C := AnsiChar(S[I]);
    if (C >= '0') and (C <= '9') then
    begin
      { leading zeros carry no value }
      if (DigitCount > 0) or (C <> '0') then
      begin
        Inc(DigitCount);
        Digits[DigitCount] := C;
      end;
      if SeenPoint then
        Inc(FracDigits);
    end
    else if (C = '.') and AllowPoint and not SeenPoint then
      SeenPoint := True
    else
      Exit;
  end;
  { at least one digit: "+", "." and "-." are invalid }
  if Last - First + 1 - Ord(SeenPoint) = 0 then
    Exit;
  if FracDigits > LandrixXmlDecimalMaxExponent then
    Exit;
  { groups of four digits from the right }
  Limbs := nil;
  SetLength(Limbs, (DigitCount + LimbDigits - 1) div LimbDigits);
  K := 0;
  ChunkEnd := DigitCount;
  while ChunkEnd >= 1 do
  begin
    ChunkStart := ChunkEnd - LimbDigits + 1;
    if ChunkStart < 1 then
      ChunkStart := 1;
    L := 0;
    for J := ChunkStart to ChunkEnd do
      L := L * 10 + (Ord(Digits[J]) - Ord('0'));
    Limbs[K] := L;
    Inc(K);
    ChunkEnd := ChunkStart - 1;
  end;
  NatTrim(Limbs);
  { values beyond the exponent limit (more than a million trailing zeros)
    are rejected like invalid input instead of raising xecArithmetic }
  if NatTrailingZeroDigits(Limbs) - FracDigits > LandrixXmlDecimalMaxExponent then
    Exit;
  Value := MakeDecimal(Negative, -FracDigits, Limbs);
  Result := True;
end;

function LandrixXmlTryParseDecimal(const S: TLandrixXmlUtf8;
  out Value: TLandrixXmlDecimal): Boolean;
begin
  Result := TryParseCore(S, True, Value);
end;

function LandrixXmlTryParseDecimalInteger(const S: TLandrixXmlUtf8;
  out Value: TLandrixXmlDecimal): Boolean;
begin
  Result := TryParseCore(S, False, Value);
end;

function LandrixXmlParseDecimal(const S: TLandrixXmlUtf8): TLandrixXmlDecimal;
begin
  if not TryParseCore(S, True, Result) then
    raise ELandrixXmlError.CreateCode(xecConversion, 'Invalid xs:decimal value "' +
      LandrixXmlEscapeForMessage(S, 40) + '"');
end;

function LandrixXmlParseDecimalInteger(const S: TLandrixXmlUtf8): TLandrixXmlDecimal;
begin
  if not TryParseCore(S, False, Result) then
    raise ELandrixXmlError.CreateCode(xecConversion, 'Invalid xs:integer value "' +
      LandrixXmlEscapeForMessage(S, 40) + '"');
end;

function LandrixXmlFormatDecimal(const A: TLandrixXmlDecimal): TLandrixXmlUtf8;
var
  Digits, Text: AnsiString;
  Frac, I: Integer;
begin
  Digits := NatToDigits(A.Limbs);
  if A.Exponent >= 0 then
  begin
    Text := Digits;
    if Length(A.Limbs) > 0 then
    begin
      SetLength(Text, Length(Digits) + A.Exponent);
      for I := Length(Digits) + 1 to Length(Text) do
        Text[I] := '0';
    end;
  end
  else
  begin
    Frac := -A.Exponent;
    if Length(Digits) > Frac then
      Text := Copy(Digits, 1, Length(Digits) - Frac) + '.' +
        Copy(Digits, Length(Digits) - Frac + 1, Frac)
    else
    begin
      SetLength(Text, Frac - Length(Digits));
      for I := 1 to Length(Text) do
        Text[I] := '0';
      Text := '0.' + Text + Digits;
    end;
  end;
  if A.Negative then
    Text := '-' + Text;
  { byte copy: a string cast would convert code pages on Delphi 2009+ }
  Result := '';
  SetLength(Result, Length(Text));
  Move(PAnsiChar(Text)^, PAnsiChar(Result)^, Length(Text));
end;

function LandrixXmlDecimalTryToInt64(const A: TLandrixXmlDecimal;
  out Value: Int64): Boolean;
var
  Full: TLandrixXmlDecimalLimbs;
  I: Integer;
  Limit: TLandrixXmlDecimal;
  Magnitude: Int64;
begin
  Value := 0;
  Result := False;
  Full := nil;
  if A.Exponent < 0 then
    Exit;
  if Length(A.Limbs) = 0 then
  begin
    Result := True;
    Exit;
  end;
  { Int64 has at most 19 digits; checked first so that huge exponents are
    never expanded }
  if NatDigitCount(A.Limbs) + A.Exponent > 19 then
    Exit;
  { magnitude limit 9223372036854775807, or ...808 for negative values }
  if A.Negative then
    Limit := LandrixXmlDecimalFromInt64(Low(Int64))
  else
    Limit := LandrixXmlDecimalFromInt64(High(Int64));
  Full := NatMulPow10(A.Limbs, A.Exponent);
  if NatCompare(Full, Limit.Limbs) > 0 then
    Exit;
  { All limbs but the lowest as a positive number (at most
    922337203685477), then one positive multiplication. Accumulating the
    negative value directly would be simpler, but the overflow-checked
    Int64 multiplication of Delphi 6 and 7 reports a false overflow for
    negative products of magnitude 2^62 and more. }
  Magnitude := 0;
  for I := Integer(Length(Full)) - 1 downto 1 do
    Magnitude := Magnitude * LimbBase + Full[I];
  Value := Magnitude * LimbBase;
  if A.Negative then
    Value := -Value - Full[0]
  else
    Value := Value + Full[0];
  Result := True;
end;

function LandrixXmlDecimalIsZero(const A: TLandrixXmlDecimal): Boolean;
begin
  Result := Length(A.Limbs) = 0;
end;

function LandrixXmlDecimalIsInteger(const A: TLandrixXmlDecimal): Boolean;
begin
  Result := A.Exponent >= 0;
end;

function LandrixXmlDecimalSign(const A: TLandrixXmlDecimal): Integer;
begin
  if Length(A.Limbs) = 0 then
    Result := 0
  else if A.Negative then
    Result := -1
  else
    Result := 1;
end;

function LandrixXmlDecimalScale(const A: TLandrixXmlDecimal): Integer;
begin
  Result := -A.Exponent;
end;

{ Coefficients of A and B on the common (smaller) exponent. }
procedure Align(const A, B: TLandrixXmlDecimal; out CA, CB: TLandrixXmlDecimalLimbs;
  out Exponent: Integer);
begin
  if A.Exponent <= B.Exponent then
  begin
    Exponent := A.Exponent;
    CA := A.Limbs;
    CB := NatMulPow10(B.Limbs, B.Exponent - A.Exponent);
  end
  else
  begin
    Exponent := B.Exponent;
    CA := NatMulPow10(A.Limbs, A.Exponent - B.Exponent);
    CB := B.Limbs;
  end;
end;

function LandrixXmlDecimalCompare(const A, B: TLandrixXmlDecimal): Integer;
var
  SA, SB, E: Integer;
  CA, CB: TLandrixXmlDecimalLimbs;
begin
  SA := LandrixXmlDecimalSign(A);
  SB := LandrixXmlDecimalSign(B);
  if SA <> SB then
  begin
    if SA < SB then
      Result := -1
    else
      Result := 1;
    Exit;
  end;
  if SA = 0 then
  begin
    Result := 0;
    Exit;
  end;
  Align(A, B, CA, CB, E);
  Result := NatCompare(CA, CB);
  if SA < 0 then
    Result := -Result;
end;

function LandrixXmlDecimalNegate(const A: TLandrixXmlDecimal): TLandrixXmlDecimal;
begin
  Result := A;
  if Length(A.Limbs) > 0 then
    Result.Negative := not A.Negative;
end;

function LandrixXmlDecimalAbs(const A: TLandrixXmlDecimal): TLandrixXmlDecimal;
begin
  Result := A;
  Result.Negative := False;
end;

function LandrixXmlDecimalAdd(const A, B: TLandrixXmlDecimal): TLandrixXmlDecimal;
var
  CA, CB: TLandrixXmlDecimalLimbs;
  E, C: Integer;
begin
  if Length(A.Limbs) = 0 then
  begin
    Result := B;
    Exit;
  end;
  if Length(B.Limbs) = 0 then
  begin
    Result := A;
    Exit;
  end;
  Align(A, B, CA, CB, E);
  if A.Negative = B.Negative then
    Result := MakeDecimal(A.Negative, E, NatAdd(CA, CB))
  else
  begin
    C := NatCompare(CA, CB);
    if C = 0 then
      Result := LandrixXmlDecimalZero
    else if C > 0 then
      Result := MakeDecimal(A.Negative, E, NatSub(CA, CB))
    else
      Result := MakeDecimal(B.Negative, E, NatSub(CB, CA));
  end;
end;

function LandrixXmlDecimalSubtract(const A, B: TLandrixXmlDecimal): TLandrixXmlDecimal;
begin
  Result := LandrixXmlDecimalAdd(A, LandrixXmlDecimalNegate(B));
end;

function LandrixXmlDecimalMultiply(const A, B: TLandrixXmlDecimal): TLandrixXmlDecimal;
begin
  if (Length(A.Limbs) = 0) or (Length(B.Limbs) = 0) then
    Result := LandrixXmlDecimalZero
  else
    Result := MakeDecimal(A.Negative <> B.Negative, A.Exponent + B.Exponent,
      NatMul(A.Limbs, B.Limbs));
end;

{ True if the truncated magnitude Quotient must be increased by one, given
  the remainder of Numerator / Denominator. Negative = sign of the exact
  result. }
function RoundsAway(const Quotient, Remainder, Denominator: TLandrixXmlDecimalLimbs;
  Negative: Boolean; Mode: TLandrixXmlDecimalRounding): Boolean;
var
  C: Integer;
begin
  Result := False;
  if Length(Remainder) = 0 then
    Exit;
  case Mode of
    xdrFloor:
      Result := Negative;
    xdrCeiling:
      Result := not Negative;
    xdrDown:
      Result := False;
  else
    C := NatCompare(NatAdd(Remainder, Remainder), Denominator);
    if C > 0 then
      Result := True
    else if C = 0 then
    begin
      case Mode of
        xdrHalfCeiling:
          Result := not Negative;
        xdrHalfEven:
          Result := NatIsOdd(Quotient);
      else
        Result := False; { xdrHalfDown }
      end;
    end;
  end;
end;

{ A / B rounded to Scale fraction digits. }
function DivideRounded(const A, B: TLandrixXmlDecimal; Scale: Integer;
  Mode: TLandrixXmlDecimalRounding): TLandrixXmlDecimal;
var
  K: Integer;
  Num, Den, Q, R: TLandrixXmlDecimalLimbs;
  Negative: Boolean;
begin
  Num := nil;
  Den := nil;
  if Length(B.Limbs) = 0 then
    RaiseArithmetic('Decimal division by zero');
  if Length(A.Limbs) = 0 then
  begin
    Result := LandrixXmlDecimalZero;
    Exit;
  end;
  if (Scale > LandrixXmlDecimalMaxExponent) or (Scale < -LandrixXmlDecimalMaxExponent) then
    RaiseArithmetic('Decimal exponent out of range');
  { A / B * 10^Scale = CA / CB * 10^K }
  K := A.Exponent - B.Exponent + Scale;
  if K >= 0 then
  begin
    Num := NatMulPow10(A.Limbs, K);
    Den := B.Limbs;
  end
  else
  begin
    Num := A.Limbs;
    Den := NatMulPow10(B.Limbs, -K);
  end;
  NatDivMod(Num, Den, Q, R);
  Negative := A.Negative <> B.Negative;
  if RoundsAway(Q, R, Den, Negative, Mode) then
    Q := NatAdd(Q, NatFromInteger(1));
  Result := MakeDecimal(Negative, -Scale, Q);
end;

function LandrixXmlDecimalDivideScaled(const A, B: TLandrixXmlDecimal;
  ScaleA, ScaleB: Integer): TLandrixXmlDecimal;
var
  Scale: Integer;
begin
  Scale := ScaleA - ScaleB + LandrixXmlDecimalDividePrecision;
  if Scale < LandrixXmlDecimalDividePrecision then
    Scale := LandrixXmlDecimalDividePrecision;
  Result := DivideRounded(A, B, Scale, xdrHalfDown);
end;

function LandrixXmlDecimalDivide(const A, B: TLandrixXmlDecimal): TLandrixXmlDecimal;
begin
  Result := LandrixXmlDecimalDivideScaled(A, B, LandrixXmlDecimalScale(A),
    LandrixXmlDecimalScale(B));
end;

{ 0 <= A <= 2^31 - 1 }
function IsSmallNonNegative(const A: TLandrixXmlDecimal; out Value: Int64): Boolean;
begin
  Result := LandrixXmlDecimalTryToInt64(A, Value) and (Value >= 0) and (Value <= High(Integer));
end;

function LandrixXmlDecimalDivideIntegers(const A, B: TLandrixXmlDecimal;
  out IsInteger: Boolean): TLandrixXmlDecimal;
var
  VA, VB: Int64;
begin
  IsInteger := False;
  if (A.Exponent < 0) or (B.Exponent < 0) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument,
      'Integer division needs integral operands');
  if Length(B.Limbs) = 0 then
    RaiseArithmetic('Integer division by zero');
  if IsSmallNonNegative(A, VA) and IsSmallNonNegative(B, VB) then
  begin
    if VA mod VB = 0 then
    begin
      IsInteger := True;
      Result := LandrixXmlDecimalFromInt64(VA div VB);
    end
    else
      Result := LandrixXmlDecimalDivideScaled(A, B, 0, 0);
  end
  else
    Result := LandrixXmlDecimalDivide(A, B);
end;

function LandrixXmlDecimalIntegerQuotient(const A, B: TLandrixXmlDecimal): TLandrixXmlDecimal;
begin
  if Length(B.Limbs) = 0 then
    RaiseArithmetic('Integer division by zero');
  Result := DivideRounded(A, B, 0, xdrDown);
end;

function LandrixXmlDecimalModulo(const A, B: TLandrixXmlDecimal): TLandrixXmlDecimal;
begin
  if Length(B.Limbs) = 0 then
    RaiseArithmetic('Modulo by zero');
  Result := LandrixXmlDecimalSubtract(A,
    LandrixXmlDecimalMultiply(B, LandrixXmlDecimalIntegerQuotient(A, B)));
end;

function LandrixXmlDecimalRound(const A: TLandrixXmlDecimal; Precision: Integer;
  Mode: TLandrixXmlDecimalRounding): TLandrixXmlDecimal;
var
  K: Integer;
  Den, Q, R: TLandrixXmlDecimalLimbs;
begin
  Den := nil;
  { checked before -Precision is computed (Low(Integer) would overflow);
    a normalized value never has more than LandrixXmlDecimalMaxExponent
    fraction digits }
  if (Length(A.Limbs) = 0) or (Precision > LandrixXmlDecimalMaxExponent) then
  begin
    Result := A;
    Exit;
  end;
  if Precision < -LandrixXmlDecimalMaxExponent then
    RaiseArithmetic('Decimal exponent out of range');
  if A.Exponent >= -Precision then
  begin
    Result := A;
    Exit;
  end;
  { drop K digits }
  K := -Precision - A.Exponent;
  if K > NatDigitCount(A.Limbs) + 1 then
  begin
    { the dropped part is below a tenth of the unit 10^-Precision: only
      floor and ceiling can move away from zero }
    if ((Mode = xdrFloor) and A.Negative) or ((Mode = xdrCeiling) and not A.Negative) then
      Q := NatFromInteger(1)
    else
      Q := nil;
  end
  else
  begin
    Den := NatPow10(K);
    NatDivMod(A.Limbs, Den, Q, R);
    if RoundsAway(Q, R, Den, A.Negative, Mode) then
      Q := NatAdd(Q, NatFromInteger(1));
  end;
  Result := MakeDecimal(A.Negative, -Precision, Q);
end;

function LandrixXmlDecimalFractionDigits(const A: TLandrixXmlDecimal): Integer;
begin
  if A.Exponent < 0 then
    Result := -A.Exponent
  else
    Result := 0;
end;

function LandrixXmlDecimalTotalDigits(const A: TLandrixXmlDecimal): Integer;
var
  Frac, Digits: Integer;
begin
  if Length(A.Limbs) = 0 then
  begin
    Result := 0;
    Exit;
  end;
  Frac := LandrixXmlDecimalFractionDigits(A);
  { digits of the integer A * 10^Frac }
  Digits := NatDigitCount(A.Limbs);
  if A.Exponent > 0 then
    Inc(Digits, A.Exponent);
  if Digits > Frac then
    Result := Digits
  else
    Result := Frac;
end;

end.
