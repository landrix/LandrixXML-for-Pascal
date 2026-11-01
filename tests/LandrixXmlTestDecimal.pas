{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for LandrixXmlDecimal: generated cases (tests/data/decimal, exact
  Python oracle checked against Saxon HE 12), lexical rules, Int64
  conversion, errors and the XML Schema digit counts. }

unit LandrixXmlTestDecimal;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlDecimal,
  LandrixXmlTestFramework;

function U(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

function N(const S: TLandrixXmlUtf8): string;
begin
  Result := LandrixXmlUtf8ToString(S);
end;

function D(const S: string): TLandrixXmlDecimal;
begin
  Result := LandrixXmlParseDecimal(U(S));
end;

function Int(const S: string): TLandrixXmlDecimal;
begin
  Result := LandrixXmlParseDecimalInteger(U(S));
end;

function F(const A: TLandrixXmlDecimal): string;
begin
  Result := N(LandrixXmlFormatDecimal(A));
end;

function DataFile(const Name: string): string;
begin
  Result := IncludeTrailingPathDelimiter(RepositoryRoot) + 'tests' + PathDelim + 'data' +
    PathDelim + 'decimal' + PathDelim + Name;
end;

{ Splits a TAB separated line into exactly four fields. }
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

{ Evaluates one generated case; division by zero gives 'error'. }
function Evaluate(const Op, A, B: string): string;
var
  V: TLandrixXmlDecimal;
  IsInt: Boolean;
begin
  try
    if Op = 'parse' then
    begin
      if LandrixXmlTryParseDecimal(U(A), V) then
        Result := F(V)
      else
        Result := 'error';
    end
    else if Op = 'add' then
      Result := F(LandrixXmlDecimalAdd(D(A), D(B)))
    else if Op = 'sub' then
      Result := F(LandrixXmlDecimalSubtract(D(A), D(B)))
    else if Op = 'mul' then
      Result := F(LandrixXmlDecimalMultiply(D(A), D(B)))
    else if Op = 'cmp' then
      Result := IntToStr(LandrixXmlDecimalCompare(D(A), D(B)))
    else if Op = 'div' then
      Result := F(LandrixXmlDecimalDivide(D(A), D(B)))
    else if Op = 'idiv' then
      Result := F(LandrixXmlDecimalIntegerQuotient(D(A), D(B)))
    else if Op = 'mod' then
      Result := F(LandrixXmlDecimalModulo(D(A), D(B)))
    else if Op = 'round' then
      Result := F(LandrixXmlDecimalRound(D(A), StrToInt(B), xdrHalfCeiling))
    else if Op = 'rhe' then
      Result := F(LandrixXmlDecimalRound(D(A), StrToInt(B), xdrHalfEven))
    else if Op = 'floor' then
      Result := F(LandrixXmlDecimalRound(D(A), 0, xdrFloor))
    else if Op = 'ceiling' then
      Result := F(LandrixXmlDecimalRound(D(A), 0, xdrCeiling))
    else if Op = 'trunc' then
      Result := F(LandrixXmlDecimalRound(D(A), 0, xdrDown))
    else if Op = 'decintdiv' then
      Result := F(LandrixXmlDecimalDivideScaled(D(A), Int(B), LandrixXmlDecimalScale(D(A)), 0))
    else if Op = 'intdecdiv' then
      Result := F(LandrixXmlDecimalDivideScaled(Int(A), D(B), 0, LandrixXmlDecimalScale(D(B))))
    else if Op = 'intdiv' then
    begin
      V := LandrixXmlDecimalDivideIntegers(Int(A), Int(B), IsInt);
      if IsInt then
        Result := F(V) + ' i'
      else
        Result := F(V) + ' d';
    end
    else
      Result := 'unknown op ' + Op;
  except
    on E: ELandrixXmlError do
    begin
      if E.Code = xecArithmetic then
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
    L.LoadFromFile(DataFile('ops.txt'));
    Check(L.Count > 5000, 'decimal cases present');
    for K := 0 to L.Count - 1 do
    begin
      SplitFields(L[K], Op, A, B, Expected);
      CheckEqualsStr(Expected, Evaluate(Op, A, B), Op + ' "' + A + '" "' + B + '"');
    end;
  finally
    L.Free;
  end;
end;

procedure CheckInvalid(const S: TLandrixXmlUtf8; AsInteger: Boolean; const Name: string);
var
  V: TLandrixXmlDecimal;
begin
  if AsInteger then
    Check(not LandrixXmlTryParseDecimalInteger(S, V), Name + ' rejected as integer')
  else
    Check(not LandrixXmlTryParseDecimal(S, V), Name + ' rejected');
  try
    if AsInteger then
      LandrixXmlParseDecimalInteger(S)
    else
      LandrixXmlParseDecimal(S);
    FailNotRaised('ELandrixXmlError for ' + Name);
  except
    on E: ELandrixXmlError do
      CheckEquals(Ord(xecConversion), Ord(E.Code), Name + ' code');
  end;
end;

procedure TestLexical;
begin
  CheckEqualsStr('12.5', F(D(#9'12.50'#13#10)), 'TAB, CR, LF trimmed');
  CheckEqualsStr('0', F(D('-0.000')), 'negative zero is zero');
  Check(not LandrixXmlDecimalZero.Negative, 'zero not negative');
  CheckEqualsStr('-0.001', F(D('-.001')), 'leading point');
  CheckEqualsStr('5', F(D('5.')), 'trailing point');
  CheckEqualsStr('123', F(Int('+00123')), 'integer with sign and zeros');
  CheckInvalid(U('1.5'), True, 'point in integer');
  CheckInvalid(U('1 000'), False, 'inner space');
  CheckInvalid(U('1,5'), False, 'comma');
  CheckInvalid(U('++1'), False, 'double sign');
  CheckInvalid(U('1E3'), False, 'exponent');
  { U+FF11 FULLWIDTH DIGIT ONE, U+0661 ARABIC-INDIC DIGIT ONE }
  CheckInvalid(Utf8Bytes([$EF, $BC, $91]), False, 'fullwidth digit');
  CheckInvalid(Utf8Bytes([$D9, $A1]), True, 'arabic-indic digit');
  CheckInvalid(Utf8Bytes([$31, $00]), False, 'embedded NUL');
  CheckInvalid(U('1' + StringOfChar('0', LandrixXmlDecimalMaxExponent + 1)), False,
    'beyond the exponent limit');
  CheckEqualsStr('1', Copy(F(D('1' + StringOfChar('0', LandrixXmlDecimalMaxExponent))), 1, 1),
    'at the exponent limit');
end;

procedure TestNormalization;
var
  V: TLandrixXmlDecimal;
begin
  V := D('2000');
  CheckEquals(3, V.Exponent, '2000 exponent');
  CheckEquals(-3, LandrixXmlDecimalScale(V), '2000 scale');
  CheckEquals(1, Integer(Length(V.Limbs)), '2000 limbs');
  CheckEquals(2, V.Limbs[0], '2000 coefficient');
  CheckEqualsStr('2000', F(V), '2000 text');
  V := D('1.50');
  CheckEquals(1, LandrixXmlDecimalScale(V), '1.50 scale');
  V := LandrixXmlDecimalMultiply(D('0.5'), D('0.2'));
  CheckEquals(1, LandrixXmlDecimalScale(V), '0.5 * 0.2 stripped');
  Check(LandrixXmlDecimalIsInteger(D('7.000')), '7.000 integral');
  Check(not LandrixXmlDecimalIsInteger(D('7.001')), '7.001 not integral');
  CheckEquals(0, LandrixXmlDecimalSign(D('0.0')), 'sign zero');
  CheckEquals(-1, LandrixXmlDecimalSign(D('-0.1')), 'sign negative');
  Check(LandrixXmlDecimalIsZero(LandrixXmlDecimalSubtract(D('1.25'), D('1.250'))), 'difference zero');
  CheckEqualsStr('-1.5', F(LandrixXmlDecimalNegate(D('1.5'))), 'negate');
  CheckEqualsStr('1.5', F(LandrixXmlDecimalNegate(D('-1.5'))), 'negate negative');
  Check(not LandrixXmlDecimalNegate(LandrixXmlDecimalZero).Negative, 'negate zero stays positive');
  CheckEqualsStr('1.5', F(LandrixXmlDecimalAbs(D('-1.5'))), 'abs');
  CheckEqualsStr('0', F(LandrixXmlDecimalAbs(LandrixXmlDecimalZero)), 'abs zero');
end;

{ Results observed with Saxon HE 12.9 (see tools/gen-decimal-testdata.py). }
procedure TestSaxonDivision;
var
  IsInt: Boolean;
begin
  CheckEqualsStr('0.333333333333333333', F(LandrixXmlDecimalDivide(D('1'), D('3'))), '1 div 3');
  CheckEqualsStr('0.2142857142857142857', F(LandrixXmlDecimalDivide(D('1.50'), D('7'))), '1.50 div 7');
  CheckEqualsStr('3666.666666666666666667', F(LandrixXmlDecimalDivide(D('1.1'), D('0.0003'))),
    '1.1 div 0.0003');
  CheckEqualsStr('0.095238095238095238142857142857142857',
    F(LandrixXmlDecimalDivide(LandrixXmlDecimalDivide(D('2'), D('3')), D('7'))), '2 div 3 div 7');
  CheckEqualsStr('6.000000000000000006',
    F(LandrixXmlDecimalDivide(D('2'), LandrixXmlDecimalDivide(D('1'), D('3')))), '2 div (1 div 3)');
  { integer operand of a decimal division: scale 0, not the normalized -3 }
  CheckEqualsStr('0.00075', F(LandrixXmlDecimalDivideScaled(D('1.5'), D('2000'), 1, 0)),
    '1.5 div 2000 (integer)');
  CheckEqualsStr('0', F(LandrixXmlDecimalDivideScaled(D('0.1'), Int('20000000000000000000'), 1, 0)),
    '0.1 div 2e19');
  { ties towards zero }
  CheckEqualsStr('0.000000000000000001',
    F(LandrixXmlDecimalDivideScaled(D('3'), D('2000000000000000000'), 0, 0)), 'half down');
  CheckEqualsStr('-0.000000000000000001',
    F(LandrixXmlDecimalDivideScaled(D('-3'), D('2000000000000000000'), 0, 0)), 'half down negative');
  { integer div integer }
  CheckEqualsStr('3', F(LandrixXmlDecimalDivideIntegers(Int('6'), Int('2'), IsInt)), '6 div 2');
  Check(IsInt, '6 div 2 is an integer');
  CheckEqualsStr('-3', F(LandrixXmlDecimalDivideIntegers(Int('-6'), Int('2'), IsInt)), '-6 div 2');
  Check(not IsInt, '-6 div 2 is a decimal');
  CheckEqualsStr('0.0000000000000000005',
    F(LandrixXmlDecimalDivideIntegers(Int('1'), Int('2000000000000000000'), IsInt)), '1 div 2e18');
  CheckEqualsStr('2.5', F(LandrixXmlDecimalDivideIntegers(Int('10'), Int('4'), IsInt)), '10 div 4');
  Check(not IsInt, '10 div 4 is a decimal');
end;

procedure CheckArithmeticError(Kind: Integer; const Name: string);
var
  IsInt: Boolean;
begin
  try
    case Kind of
      0: LandrixXmlDecimalDivide(D('1'), D('0.0'));
      1: LandrixXmlDecimalIntegerQuotient(D('1'), D('0'));
      2: LandrixXmlDecimalModulo(D('1'), D('0'));
      3: LandrixXmlDecimalDivideIntegers(Int('1'), Int('0'), IsInt);
    else
      Fail('unknown kind');
    end;
    FailNotRaised('ELandrixXmlError for ' + Name);
  except
    on E: ELandrixXmlError do
      CheckEquals(Ord(xecArithmetic), Ord(E.Code), Name + ' code: ' + E.Message);
  end;
end;

procedure TestErrors;
var
  Big: TLandrixXmlDecimal;
  IsInt: Boolean;
begin
  CheckArithmeticError(0, 'div by zero');
  CheckArithmeticError(1, 'idiv by zero');
  CheckArithmeticError(2, 'mod by zero');
  CheckArithmeticError(3, 'integer div by zero');
  try
    LandrixXmlDecimalDivideIntegers(D('1.5'), Int('1'), IsInt);
    FailNotRaised('ELandrixXmlError for fraction in integer division');
  except
    on E: ELandrixXmlError do
      CheckEquals(Ord(xecInvalidArgument), Ord(E.Code), 'fraction in integer division');
  end;
  { exponent limit: 10^600000 squared exceeds the limit }
  Big := LandrixXmlDecimalRound(D('7'), -600000, xdrCeiling);
  CheckEquals(600000, Big.Exponent, 'huge exponent allowed');
  { a unit beyond the exponent range: 0, or an error if the result is not 0 }
  CheckEqualsStr('0', F(LandrixXmlDecimalRound(D('-7'), -2000000, xdrHalfEven)), 'unit 10^2000000');
  CheckEqualsStr('0', F(LandrixXmlDecimalRound(D('7'), Low(Integer), xdrHalfCeiling)), 'Low(Integer)');
  CheckEqualsStr('0', F(LandrixXmlDecimalRound(D('7'), -2000000, xdrFloor)), 'floor 7');
  CheckEqualsStr('0', F(LandrixXmlDecimalRound(D('-7'), Low(Integer), xdrCeiling)), 'ceiling -7');
  try
    LandrixXmlDecimalRound(D('7'), -2000000, xdrCeiling);
    FailNotRaised('ELandrixXmlError for ceiling to 10^2000000');
  except
    on E: ELandrixXmlError do
      CheckEquals(Ord(xecArithmetic), Ord(E.Code), 'ceiling to 10^2000000');
  end;
  try
    LandrixXmlDecimalMultiply(Big, Big);
    FailNotRaised('ELandrixXmlError for exponent overflow');
  except
    on E: ELandrixXmlError do
      CheckEquals(Ord(xecArithmetic), Ord(E.Code), 'exponent overflow');
  end;
end;

procedure TestInt64;
var
  V: Int64;
begin
  CheckEqualsStr('-9223372036854775808', F(LandrixXmlDecimalFromInt64(Low(Int64))), 'Low(Int64)');
  CheckEqualsStr('9223372036854775807', F(LandrixXmlDecimalFromInt64(High(Int64))), 'High(Int64)');
  CheckEqualsStr('-10000', F(LandrixXmlDecimalFromInt64(-10000)), '-10000');
  Check(LandrixXmlDecimalTryToInt64(Int('-9223372036854775808'), V), 'Low(Int64) back');
  Check(V = Low(Int64), 'Low(Int64) value');
  Check(LandrixXmlDecimalTryToInt64(Int('9223372036854775807'), V), 'High(Int64) back');
  Check(V = High(Int64), 'High(Int64) value');
  Check(not LandrixXmlDecimalTryToInt64(Int('9223372036854775808'), V), 'High(Int64) + 1');
  Check(not LandrixXmlDecimalTryToInt64(Int('-9223372036854775809'), V), 'Low(Int64) - 1');
  Check(not LandrixXmlDecimalTryToInt64(D('1.5'), V), 'fraction');
  Check(LandrixXmlDecimalTryToInt64(D('12000'), V), '12000 (exponent 3)');
  CheckEqualsInt64(12000, V, '12000 value');
  Check(LandrixXmlDecimalTryToInt64(Int('-9223372036854775807'), V), '-High(Int64)');
  Check(V = -High(Int64), '-High(Int64) value');
  Check(LandrixXmlDecimalTryToInt64(Int('-4611686018427387905'), V), 'below -2^62');
  { compared as numbers: IntToStr(Int64) of Delphi 7 misbehaves in the x86
    emulator of the ARM development machine }
  Check(V = -4611686018427387905, 'below -2^62 value');
  Check(LandrixXmlDecimalTryToInt64(Int('-7'), V), '-7');
  CheckEqualsInt64(-7, V, '-7 value');
  Check(not LandrixXmlDecimalTryToInt64(LandrixXmlDecimalRound(D('7'), -600000, xdrCeiling), V),
    'huge exponent');
  Check(LandrixXmlDecimalTryToInt64(LandrixXmlDecimalZero, V), 'zero');
  CheckEqualsInt64(0, V, 'zero value');
end;

procedure TestRoundingModes;
begin
  CheckEqualsStr('3', F(LandrixXmlDecimalRound(D('2.5'), 0, xdrHalfCeiling)), 'round 2.5');
  CheckEqualsStr('-2', F(LandrixXmlDecimalRound(D('-2.5'), 0, xdrHalfCeiling)), 'round -2.5');
  CheckEqualsStr('-3', F(LandrixXmlDecimalRound(D('-2.51'), 0, xdrHalfCeiling)), 'round -2.51');
  CheckEqualsStr('2', F(LandrixXmlDecimalRound(D('2.5'), 0, xdrHalfEven)), 'rhe 2.5');
  CheckEqualsStr('4', F(LandrixXmlDecimalRound(D('3.5'), 0, xdrHalfEven)), 'rhe 3.5');
  CheckEqualsStr('-2', F(LandrixXmlDecimalRound(D('-2.5'), 0, xdrHalfDown)), 'half down -2.5');
  CheckEqualsStr('1200', F(LandrixXmlDecimalRound(D('1234'), -2, xdrHalfCeiling)), 'round to hundreds');
  CheckEqualsStr('1.26', F(LandrixXmlDecimalRound(D('1.255'), 2, xdrHalfCeiling)), 'round 1.255');
  { far below the unit }
  CheckEqualsStr('0', F(LandrixXmlDecimalRound(D('0.0000001'), -5, xdrHalfCeiling)), 'tiny half');
  CheckEqualsStr('100000', F(LandrixXmlDecimalRound(D('0.0000001'), -5, xdrCeiling)), 'tiny ceiling');
  CheckEqualsStr('-100000', F(LandrixXmlDecimalRound(D('-0.0000001'), -5, xdrFloor)), 'tiny floor');
  CheckEqualsStr('0', F(LandrixXmlDecimalRound(D('-0.0000001'), -5, xdrCeiling)), 'tiny negative ceiling');
  CheckEqualsStr('1.5', F(LandrixXmlDecimalRound(D('1.5'), High(Integer), xdrHalfCeiling)),
    'precision High(Integer)');
  CheckEqualsStr('0', F(LandrixXmlDecimalRound(D('1.5'), Low(Integer), xdrHalfCeiling)),
    'precision Low(Integer)');
end;

procedure TestDigits;
begin
  CheckEquals(0, LandrixXmlDecimalTotalDigits(D('0')), 'total 0');
  CheckEquals(1, LandrixXmlDecimalTotalDigits(D('0.5')), 'total 0.5');
  CheckEquals(2, LandrixXmlDecimalTotalDigits(D('0.05')), 'total 0.05');
  CheckEquals(3, LandrixXmlDecimalTotalDigits(D('1.05')), 'total 1.05');
  CheckEquals(4, LandrixXmlDecimalTotalDigits(D('1200')), 'total 1200');
  CheckEquals(3, LandrixXmlDecimalTotalDigits(D('-001.2300')), 'total -001.2300');
  CheckEquals(0, LandrixXmlDecimalFractionDigits(D('1200')), 'fraction 1200');
  CheckEquals(2, LandrixXmlDecimalFractionDigits(D('-001.2300')), 'fraction -001.2300');
end;

{ IBAN check of the XRechnung rules: a 34 character IBAN becomes an
  integer of up to 68 digits, then mod 97. }
procedure TestLargeIntegers;
var
  V: TLandrixXmlDecimal;
begin
  V := Int('11111111111111111111111111111111111111111111111111111111111111111111');
  CheckEqualsStr('78', F(LandrixXmlDecimalModulo(V, Int('97'))), '68 digits mod 97');
  { DE89 3704 0044 0532 0130 00 rearranged: 370400440532013000131489 }
  CheckEqualsStr('1', F(LandrixXmlDecimalModulo(Int('370400440532013000131489'), Int('97'))),
    'IBAN check sum');
  CheckEqualsStr('121932631137021795226185032733622923332237463801111263526900',
    F(LandrixXmlDecimalMultiply(Int('123456789012345678901234567890'),
    Int('987654321098765432109876543210'))), 'long product');
end;

procedure Register;
begin
  RegisterTest('Decimal.GeneratedData', TestGeneratedData);
  RegisterTest('Decimal.Lexical', TestLexical);
  RegisterTest('Decimal.Normalization', TestNormalization);
  RegisterTest('Decimal.SaxonDivision', TestSaxonDivision);
  RegisterTest('Decimal.Errors', TestErrors);
  RegisterTest('Decimal.Int64', TestInt64);
  RegisterTest('Decimal.RoundingModes', TestRoundingModes);
  RegisterTest('Decimal.Digits', TestDigits);
  RegisterTest('Decimal.LargeIntegers', TestLargeIntegers);
end;

end.
