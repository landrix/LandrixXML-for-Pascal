{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for LandrixXmlDouble: generated cases (tests/data/double, Python as
  IEEE oracle, checked against Saxon HE 12), special values, Saxon's
  formatting quirks, the conversions to native Double and xs:float
  (float-cases.txt, exact fractions as oracle). }

unit LandrixXmlTestDouble;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlDecimal,
  LandrixXmlDouble,
  LandrixXmlTestFramework;

function U(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

function N(const S: TLandrixXmlUtf8): string;
begin
  Result := LandrixXmlUtf8ToString(S);
end;

function Dbl(const S: string): TLandrixXmlDouble;
begin
  Result := LandrixXmlDoubleParse(U(S));
end;

function DblStr(const A: TLandrixXmlDouble): string;
begin
  Result := N(LandrixXmlDoubleFormat(A));
end;

function HexDigit(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
  else
    Result := -1;
  end;
end;

{ 16 hex digits -> bit pattern (shifting avoids literals above High(Int64)) }
function FromHex(const S: string): TLandrixXmlDouble;
var
  I: Integer;
  Bits: Int64;
begin
  if Length(S) <> 16 then
    Fail('bad hex value "' + S + '"');
  Bits := 0;
  for I := 1 to 16 do
  begin
    if HexDigit(S[I]) < 0 then
      Fail('bad hex value "' + S + '"');
    Bits := (Bits shl 4) or HexDigit(S[I]);
  end;
  Result := LandrixXmlDoubleFromBits(Bits);
end;

function ToHex(const A: TLandrixXmlDouble): string;
const
  Digits: string = '0123456789ABCDEF';
var
  I: Integer;
  Bits: Int64;
begin
  Result := '';
  Bits := A.Bits;
  for I := 1 to 16 do
  begin
    Result := Digits[Integer(Bits and 15) + 1] + Result;
    Bits := Bits shr 4;
  end;
end;

function DataFile(const Name: string): string;
begin
  Result := IncludeTrailingPathDelimiter(RepositoryRoot) + 'tests' + PathDelim + 'data' +
    PathDelim + 'double' + PathDelim + Name;
end;

procedure SplitFields(const Line: string; out Op, A, B, Expected: string);
var
  Rest: string;
  P: Integer;
begin
  Rest := Line;
  P := Pos(#9, Rest);
  Op := Copy(Rest, 1, P - 1);
  Rest := Copy(Rest, P + 1, MaxInt);
  P := Pos(#9, Rest);
  A := Copy(Rest, 1, P - 1);
  Rest := Copy(Rest, P + 1, MaxInt);
  P := Pos(#9, Rest);
  B := Copy(Rest, 1, P - 1);
  Expected := Copy(Rest, P + 1, MaxInt);
end;

function Evaluate(const Op, A, B: string): string;
var
  V: TLandrixXmlDouble;
begin
  try
    if Op = 'parse' then
    begin
      if LandrixXmlDoubleTryParse(U(A), V) then
        Result := ToHex(V)
      else
        Result := 'error';
    end
    else if Op = 'format' then
      Result := DblStr(FromHex(A))
    else if Op = 'todecimal' then
      Result := N(LandrixXmlFormatDecimal(LandrixXmlDoubleToDecimal(FromHex(A))))
    else if Op = 'tointeger' then
      Result := N(LandrixXmlFormatDecimal(LandrixXmlDoubleToInteger(FromHex(A))))
    else if Op = 'fromdecimal' then
      Result := ToHex(LandrixXmlDoubleFromDecimal(LandrixXmlParseDecimal(U(A))))
    else if Op = 'add' then
      Result := ToHex(LandrixXmlDoubleAdd(FromHex(A), FromHex(B)))
    else if Op = 'sub' then
      Result := ToHex(LandrixXmlDoubleSubtract(FromHex(A), FromHex(B)))
    else if Op = 'mul' then
      Result := ToHex(LandrixXmlDoubleMultiply(FromHex(A), FromHex(B)))
    else if Op = 'div' then
      Result := ToHex(LandrixXmlDoubleDivide(FromHex(A), FromHex(B)))
    else if Op = 'mod' then
      Result := ToHex(LandrixXmlDoubleModulo(FromHex(A), FromHex(B)))
    else if Op = 'cmp' then
      Result := IntToStr(LandrixXmlDoubleCompare(FromHex(A), FromHex(B)))
    else if Op = 'round' then
      Result := ToHex(LandrixXmlDoubleRound(FromHex(A), StrToInt(B), xdrHalfCeiling))
    else if Op = 'rhe' then
      Result := ToHex(LandrixXmlDoubleRound(FromHex(A), StrToInt(B), xdrHalfEven))
    else if Op = 'floor' then
      Result := ToHex(LandrixXmlDoubleRound(FromHex(A), 0, xdrFloor))
    else if Op = 'ceiling' then
      Result := ToHex(LandrixXmlDoubleRound(FromHex(A), 0, xdrCeiling))
    else
      Result := 'unknown op ' + Op;
  except
    on E: ELandrixXmlError do
    begin
      if E.Code = xecConversion then
        Result := 'error'
      else
        Result := 'unexpected error: ' + E.Message;
    end;
  end;
end;

procedure TestGeneratedData;
var
  L: TStringList;
  K: Integer;
  Op, A, B, Expected: string;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(DataFile('cases.txt'));
    Check(L.Count > 8000, 'double cases present');
    for K := 0 to L.Count - 1 do
    begin
      SplitFields(L[K], Op, A, B, Expected);
      CheckEqualsStr(Expected, Evaluate(Op, A, B), Op + ' "' + A + '" "' + B + '"');
    end;
  finally
    L.Free;
  end;
end;

{ xs:float: tools/gen-float-testdata.py }
function EvaluateFloat(const Op, A: string): string;
var
  V: TLandrixXmlDouble;
begin
  try
    if Op = 'roundtofloat' then
      Result := ToHex(LandrixXmlDoubleRoundToFloat(FromHex(A)))
    else if Op = 'isfloat' then
    begin
      if LandrixXmlDoubleIsFloat(FromHex(A)) then
        Result := 'true'
      else
        Result := 'false';
    end
    else if Op = 'parse' then
    begin
      if LandrixXmlDoubleTryParseFloat(U(A), V) then
        Result := ToHex(V)
      else
        Result := 'error';
    end
    else if Op = 'fromdecimal' then
      Result := ToHex(LandrixXmlDoubleFloatFromDecimal(LandrixXmlParseDecimal(U(A))))
    else if Op = 'format' then
      Result := N(LandrixXmlDoubleFormatFloat(FromHex(A)))
    else
      Result := 'unknown op ' + Op;
  except
    on E: ELandrixXmlError do
      Result := 'unexpected error: ' + E.Message;
  end;
end;

procedure TestFloatData;
var
  L: TStringList;
  K: Integer;
  Op, A, B, Expected: string;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(DataFile('float-cases.txt'));
    Check(L.Count > 5000, 'float cases present');
    for K := 0 to L.Count - 1 do
    begin
      SplitFields(L[K], Op, A, B, Expected);
      CheckEqualsStr(Expected, EvaluateFloat(Op, A), 'float ' + Op + ' "' + A + '"');
    end;
  finally
    L.Free;
  end;
end;

{ The raising variant and a double that is not a float. }
procedure TestFloatApi;
var
  Raised: Boolean;
begin
  CheckEqualsStr('0.1', N(LandrixXmlDoubleFormatFloat(Dbl('0.1'))), 'format rounds to float first');
  CheckEqualsStr('3FB99999A0000000', ToHex(LandrixXmlDoubleParseFloat(U('0.1'))), 'ParseFloat');
  Check(not LandrixXmlDoubleIsFloat(Dbl('0.1')), 'the double 0.1 is no float');
  Check(LandrixXmlDoubleIsFloat(LandrixXmlDoubleParseFloat(U('0.1'))), 'the float 0.1 is');
  Raised := False;
  try
    LandrixXmlDoubleParseFloat(U('1,5'));
  except
    on E: ELandrixXmlError do
      Raised := E.Code = xecConversion;
  end;
  Check(Raised, 'invalid xs:float raises xecConversion');
end;

procedure TestSpecialValues;
var
  Nan, Inf, NegInf: TLandrixXmlDouble;
begin
  Nan := LandrixXmlDoubleNaN;
  Inf := LandrixXmlDoubleInfinity(False);
  NegInf := LandrixXmlDoubleInfinity(True);
  CheckEqualsStr('NaN', DblStr(Nan), 'NaN');
  CheckEqualsStr('INF', DblStr(Inf), 'INF');
  CheckEqualsStr('-INF', DblStr(NegInf), '-INF');
  CheckEqualsStr('-0', DblStr(LandrixXmlDoubleZero(True)), '-0');
  Check(LandrixXmlDoubleIsNaN(Nan), 'IsNaN');
  Check(not LandrixXmlDoubleSignBit(Nan), 'NaN has no sign');
  Check(LandrixXmlDoubleIsInfinite(NegInf) and LandrixXmlDoubleSignBit(NegInf), '-INF');
  Check(LandrixXmlDoubleIsZero(LandrixXmlDoubleZero(True)), '-0 is zero');
  CheckEquals(LandrixXmlDoubleUnordered, LandrixXmlDoubleCompare(Nan, Nan), 'NaN unordered');
  CheckEquals(0, LandrixXmlDoubleCompare(LandrixXmlDoubleZero(True), LandrixXmlDoubleZero(False)),
    '-0 = +0');
  { any NaN pattern becomes the canonical one }
  CheckEqualsStr('7FF8000000000000', ToHex(FromHex('FFF0000000000001')), 'NaN canonical');
  CheckEqualsStr('7FF8000000000000', ToHex(LandrixXmlDoubleNegate(Nan)), '-NaN');
  CheckEqualsStr('INF', DblStr(LandrixXmlDoubleDivide(Dbl('1'), Dbl('0'))), '1 div 0e0');
  CheckEqualsStr('-INF', DblStr(LandrixXmlDoubleDivide(Dbl('-1'), Dbl('0'))), '-1 div 0e0');
  CheckEqualsStr('-INF', DblStr(LandrixXmlDoubleDivide(Dbl('1'), Dbl('-0'))), '1 div -0e0');
  CheckEqualsStr('NaN', DblStr(LandrixXmlDoubleDivide(Dbl('0'), Dbl('0'))), '0 div 0e0');
  CheckEqualsStr('NaN', DblStr(LandrixXmlDoubleModulo(Dbl('5'), Dbl('0'))), '5 mod 0e0');
  CheckEqualsStr('-0', DblStr(LandrixXmlDoubleModulo(Dbl('-6'), Dbl('3'))), '-6 mod 3e0');
  CheckEqualsStr('NaN', DblStr(LandrixXmlDoubleAdd(Inf, NegInf)), 'INF + -INF');
  CheckEqualsStr('NaN', DblStr(LandrixXmlDoubleMultiply(Inf, Dbl('0'))), 'INF * 0');
end;

procedure TestNoExtendedRange;
var
  V: TLandrixXmlDouble;
begin
  { an x87 keeps 1e308 * 10 finite in its extended exponent range }
  V := LandrixXmlDoubleDivide(LandrixXmlDoubleMultiply(Dbl('1e308'), Dbl('10')), Dbl('10'));
  CheckEqualsStr('INF', DblStr(V), '1e308 * 10 div 10');
  { double rounding of a subnormal result on an x87 at 53-bit precision:
    0x1.0000000000001p-1022 * 0.5 is exactly halfway and rounds to even }
  V := LandrixXmlDoubleMultiply(FromHex('0010000000000001'), Dbl('0.5'));
  CheckEqualsStr('0008000000000000', ToHex(V), 'subnormal tie to even');
  V := LandrixXmlDoubleMultiply(FromHex('0010000000000003'), Dbl('0.5'));
  CheckEqualsStr('0008000000000002', ToHex(V), 'subnormal tie to even upwards');
end;

{ Strings observed with Saxon HE 12.9. }
procedure TestSaxonFormatting;
begin
  CheckEqualsStr('0.1', DblStr(Dbl('0.1')), '0.1');
  CheckEqualsStr('0.30000000000000004', DblStr(LandrixXmlDoubleAdd(Dbl('0.1'), Dbl('0.2'))), '0.1 + 0.2');
  CheckEqualsStr('1.0E6', DblStr(Dbl('1e6')), '1e6');
  CheckEqualsStr('999999.9', DblStr(Dbl('999999.9')), '999999.9');
  CheckEqualsStr('0.000001', DblStr(Dbl('1e-6')), '1e-6');
  CheckEqualsStr('9.99E-7', DblStr(Dbl('9.99e-7')), '9.99e-7');
  CheckEqualsStr('100', DblStr(Dbl('100')), '100');
  CheckEqualsStr('1.0E21', DblStr(Dbl('1e21')), '1e21');
  CheckEqualsStr('0.9999999999999999E23', DblStr(Dbl('1e23')), '1e23 (Saxon quirk)');
  CheckEqualsStr('1.2345678901234567E19', DblStr(Dbl('12345678901234567890')), '20 digits');
  CheckEqualsStr('5.682808141412917E14', DblStr(Dbl('568280814141291.75')), 'tie to the lower digit');
  CheckEqualsStr('-4.2185946858501776E16', DblStr(Dbl('-42185946858501776')), 'exclusive boundary');
  CheckEqualsStr('1.7976931348623157E308', DblStr(Dbl('1.7976931348623157e308')), 'max');
  CheckEqualsStr('4.9E-324', DblStr(Dbl('4.9e-324')), 'min subnormal');
  CheckEqualsStr('-0.00125', DblStr(Dbl('-1.25E-3')), '-1.25E-3');
end;

procedure TestParsing;
var
  V: TLandrixXmlDouble;
begin
  CheckEqualsStr('12', DblStr(Dbl(' 12 ')), 'white space');
  CheckEqualsStr('INF', DblStr(Dbl('+INF')), '+INF');
  CheckEqualsStr('0.5', DblStr(Dbl('.5')), '.5');
  CheckEqualsStr('1', DblStr(Dbl('1.')), '1.');
  CheckEqualsStr('INF', DblStr(Dbl('1e400')), 'overflow');
  CheckEqualsStr('-0', DblStr(Dbl('-1e-400')), 'underflow keeps the sign');
  Check(not LandrixXmlDoubleTryParse(U('-NaN'), V), '-NaN');
  Check(not LandrixXmlDoubleTryParse(U('inf'), V), 'inf');
  Check(not LandrixXmlDoubleTryParse(U('1e'), V), '1e');
  Check(not LandrixXmlDoubleTryParse(U('1 e5'), V), 'space before exponent');
  Check(not LandrixXmlDoubleTryParse(U(''), V), 'empty');
  Check(not LandrixXmlDoubleTryParse(Utf8Bytes([$31, $00]), V), 'embedded NUL');
  CheckEqualsStr('100000', DblStr(Dbl('1.e5')), '1.e5');
  CheckEqualsStr('INF', DblStr(Dbl('INF ')), 'INF with trailing white space');
  Check(not LandrixXmlDoubleTryParse(U('+NaN'), V), '+NaN');
  Check(not LandrixXmlDoubleTryParse(U('1e+'), V), '1e+');
  Check(not LandrixXmlDoubleTryParse(U('1e-'), V), '1e-');
  Check(not LandrixXmlDoubleTryParse(Utf8Bytes([$31, $0B]), V), 'vertical tab is no white space');
  try
    LandrixXmlDoubleParse(U('abc'));
    FailNotRaised('ELandrixXmlError for abc');
  except
    on E: ELandrixXmlError do
      CheckEquals(Ord(xecConversion), Ord(E.Code), 'abc');
  end;
end;

{ Very long inputs: the exponent limit depends on the input length, and
  only 800 significant digits are kept. }
procedure TestLongInputs;
var
  Started: TDateTime;
begin
  Started := Now;
  CheckEqualsStr('INF', DblStr(Dbl('0.' + StringOfChar('0', 300000) + '1e3000000')),
    'exponent beyond a long fraction');
  CheckEqualsStr('0', DblStr(Dbl('1' + StringOfChar('0', 300000) + 'e-3000000')),
    'negative exponent beyond a long integer');
  CheckEqualsStr('1', DblStr(Dbl('1' + StringOfChar('0', 20000) + 'e-20000')), 'long integer part');
  CheckEqualsStr('0.1', DblStr(Dbl('0.1' + StringOfChar('0', 20000))), 'long fraction');
  { a dropped non-zero digit decides a tie: 2^53 + 1 lies halfway }
  CheckEqualsStr('9.007199254740994E15',
    DblStr(Dbl('9007199254740993.' + StringOfChar('0', 1000) + '1')), 'tie broken by significant digit 1017');
  CheckEqualsStr('9.007199254740992E15',
    DblStr(Dbl('9007199254740993.' + StringOfChar('0', 1000))), 'exact tie to even');
  CheckEqualsStr('0.1', DblStr(LandrixXmlDoubleFromDecimal(LandrixXmlParseDecimal(
    U('0.1' + StringOfChar('0', 5000) + '1')))), 'long decimal');
  CheckEqualsStr('0.1', DblStr(LandrixXmlDoubleFromDecimal(LandrixXmlParseDecimal(
    U('0.1' + StringOfChar('0', 300000) + '1')))), 'very long decimal');
  CheckEqualsStr('INF', DblStr(LandrixXmlDoubleFromDecimal(LandrixXmlDecimalMultiplyPow10(
    LandrixXmlParseDecimal(U('1' + StringOfChar('0', 900) + '1')), 999000))),
    'long decimal near the exponent limit');
  Check(Now - Started < 20 / (24 * 3600), 'well below 20 seconds');
end;

procedure TestConversions;
var
  V: TLandrixXmlDouble;
begin
  CheckEqualsStr('0.1000000000000000055511151231257827021181583404541015625',
    N(LandrixXmlFormatDecimal(LandrixXmlDoubleToDecimal(Dbl('0.1')))), 'exact 0.1');
  CheckEqualsStr('2', N(LandrixXmlFormatDecimal(LandrixXmlDoubleToInteger(Dbl('2.9')))), 'trunc 2.9');
  CheckEqualsStr('-2', N(LandrixXmlFormatDecimal(LandrixXmlDoubleToInteger(Dbl('-2.9')))), 'trunc -2.9');
  CheckEqualsStr('1361129467683754000000000000000000000000',
    N(LandrixXmlFormatDecimal(LandrixXmlDoubleToInteger(Dbl('1.361129467683754e39')))), '2^130');
  try
    LandrixXmlDoubleToInteger(LandrixXmlDoubleNaN);
    FailNotRaised('ELandrixXmlError for xs:integer(NaN)');
  except
    on E: ELandrixXmlError do
      CheckEquals(Ord(xecConversion), Ord(E.Code), 'xs:integer(NaN)');
  end;
  CheckEqualsStr('0.1', DblStr(LandrixXmlDoubleFromDecimal(LandrixXmlParseDecimal(U('0.1')))), 'from 0.1');
  CheckEqualsStr('-9.223372036854776E18', DblStr(LandrixXmlDoubleFromInt64(Low(Int64))), 'Low(Int64)');
  { native round trip by bit copy }
  V := LandrixXmlDoubleFromNative(LandrixXmlDoubleToNative(Dbl('123.25')));
  CheckEqualsStr('123.25', DblStr(V), 'native round trip');
  CheckEqualsStr('405ED00000000000', ToHex(V), 'native bits');
end;

procedure TestRounding;
begin
  CheckEqualsStr('3', DblStr(LandrixXmlDoubleRound(Dbl('2.5'), 0, xdrHalfCeiling)), 'round 2.5');
  CheckEqualsStr('-2', DblStr(LandrixXmlDoubleRound(Dbl('-2.5'), 0, xdrHalfCeiling)), 'round -2.5');
  CheckEqualsStr('-0', DblStr(LandrixXmlDoubleRound(Dbl('-0.4'), 0, xdrHalfCeiling)), 'round -0.4');
  CheckEqualsStr('2', DblStr(LandrixXmlDoubleRound(Dbl('2.5'), 0, xdrHalfEven)), 'rhe 2.5');
  CheckEqualsStr('1.25', DblStr(LandrixXmlDoubleRound(Dbl('1.255'), 2, xdrHalfCeiling)), 'round 1.255');
  CheckEqualsStr('-1', DblStr(LandrixXmlDoubleRound(Dbl('-0.5'), 0, xdrFloor)), 'floor -0.5');
  CheckEqualsStr('-0', DblStr(LandrixXmlDoubleRound(Dbl('-0.5'), 0, xdrCeiling)), 'ceiling -0.5');
  CheckEqualsStr('NaN', DblStr(LandrixXmlDoubleRound(LandrixXmlDoubleNaN, 0, xdrHalfCeiling)), 'round NaN');
  CheckEqualsStr('1.0E300', DblStr(LandrixXmlDoubleRound(Dbl('1e300'), 0, xdrHalfCeiling)), 'round 1e300');
  CheckEqualsStr('0.1', DblStr(LandrixXmlDoubleRound(Dbl('0.1'), MaxInt, xdrHalfCeiling)), 'precision MaxInt');
  CheckEqualsStr('0', DblStr(LandrixXmlDoubleRound(Dbl('123.4'), -MaxInt, xdrHalfCeiling)), 'precision -MaxInt');
  CheckEqualsStr('-INF', DblStr(LandrixXmlDoubleRound(Dbl('-123.4'), -2000000, xdrFloor)),
    'floor to a huge unit');
  CheckEqualsStr('-0', DblStr(LandrixXmlDoubleRound(Dbl('-123.4'), -2000000, xdrCeiling)),
    'ceiling to a huge unit');
end;

procedure Register;
begin
  RegisterTest('Double.GeneratedData', TestGeneratedData);
  RegisterTest('Double.SpecialValues', TestSpecialValues);
  RegisterTest('Double.NoExtendedRange', TestNoExtendedRange);
  RegisterTest('Double.SaxonFormatting', TestSaxonFormatting);
  RegisterTest('Double.Parsing', TestParsing);
  RegisterTest('Double.LongInputs', TestLongInputs);
  RegisterTest('Double.Conversions', TestConversions);
  RegisterTest('Double.Rounding', TestRounding);
  RegisterTest('Double.FloatData', TestFloatData);
  RegisterTest('Double.FloatApi', TestFloatApi);
end;

end.
