{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for LandrixXmlConvert and the base64 decoder: generated cases
  (tests/data/convert, Python decimal/struct as oracle), lexical rules,
  ranges, error codes and offsets, dates, CII formats, locale
  independence. }

unit LandrixXmlTestConvert;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlConvert,
  LandrixXmlTestFramework;

function U(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

function N(const S: TLandrixXmlUtf8): string;
begin
  Result := LandrixXmlUtf8ToString(S);
end;

function DataFile(const Name: string): string;
begin
  Result := IncludeTrailingPathDelimiter(RepositoryRoot) + 'tests' + PathDelim + 'data' +
    PathDelim + 'convert' + PathDelim + Name;
end;

{ Splits "a TAB b [TAB c]". }
procedure SplitLine(const Line: string; out A, B, C: string);
var
  P: Integer;
  Rest: string;
begin
  P := Pos(#9, Line);
  A := Copy(Line, 1, P - 1);
  Rest := Copy(Line, P + 1, MaxInt);
  P := Pos(#9, Rest);
  if P = 0 then
  begin
    B := Rest;
    C := '';
  end
  else
  begin
    B := Copy(Rest, 1, P - 1);
    C := Copy(Rest, P + 1, MaxInt);
  end;
end;

{ The parse call must raise xecConversion at Offset. Kind selects the
  parser. }
procedure Bad(Kind: Integer; const S: string; Offset: Integer; const Name: string);
var
  V: TLandrixXmlUtf8;
begin
  V := U(S);
  try
    case Kind of
      0: LandrixXmlParseCurrency(V);
      1: LandrixXmlParseDouble(V);
      2: LandrixXmlParseInt64(V);
      3: LandrixXmlParseInteger(V);
      4: LandrixXmlParseBoolean(V);
      5: LandrixXmlParseDateParts(V);
      6: LandrixXmlParseDateTimeParts(V);
      7: LandrixXmlParseTimeParts(V);
      8: LandrixXmlParseCiiDateParts(V, 102);
      9: LandrixXmlParseCiiDateParts(V, 610);
    else
      Fail('unknown kind');
    end;
    FailNotRaised('ELandrixXmlError for ' + Name);
  except
    on E: ELandrixXmlError do
    begin
      CheckEquals(Ord(xecConversion), Ord(E.Code), Name + ' (code; message: ' + E.Message + ')');
      if Offset >= 0 then
        CheckEqualsInt64(Offset, E.Offset, Name + ' (offset; message: ' + E.Message + ')');
    end;
  end;
end;

{ Doubles from text at run time: literals that are not exactly
  representable raise W1066 on Delphi Win64. }
function Dbl(const S: string): Double;
begin
  Result := LandrixXmlParseDouble(U(S));
end;

function Cur(const S: string): string;
begin
  Result := N(LandrixXmlFormatCurrency(LandrixXmlParseCurrency(U(S)), 4));
end;

procedure ExpectArgError(Kind: Integer; const Name: string);
var
  NaN: Double;
begin
  PInt64(@NaN)^ := $7FF8000000000000;
  try
    case Kind of
      0: LandrixXmlFormatCurrency(1, -1);
      1: LandrixXmlFormatCurrency(1, 19);
      2: LandrixXmlFormatCurrencyTrim(1, 3, 2);
      3: LandrixXmlFormatDouble(NaN, 2);
      4: LandrixXmlFormatDateTimeTz(0, 900);
      5: LandrixXmlFormatCiiDate(0, 616);
    end;
    FailNotRaised('ELandrixXmlError for ' + Name);
  except
    on E: ELandrixXmlError do
      CheckEquals(Ord(xecInvalidArgument), Ord(E.Code), Name + ' (code; message: ' + E.Message + ')');
  end;
end;

{ --- generated cases ---------------------------------------------------------- }

procedure TestCurrencyData;
var
  L: TStringList;
  I: Integer;
  A, B, C: string;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(DataFile('currency.txt'));
    Check(L.Count > 1000, 'currency cases present');
    for I := 0 to L.Count - 1 do
    begin
      SplitLine(L[I], A, B, C);
      CheckEqualsStr(C, N(LandrixXmlFormatCurrency(LandrixXmlParseCurrency(U(A)),
        StrToInt(B))), 'currency ' + A + ' with ' + B + ' decimals');
    end;
  finally
    L.Free;
  end;
end;

procedure TestDoubleFormatData;
var
  L: TStringList;
  I: Integer;
  A, B, C: string;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(DataFile('double-format.txt'));
    Check(L.Count > 1000, 'double format cases present');
    for I := 0 to L.Count - 1 do
    begin
      SplitLine(L[I], A, B, C);
      CheckEqualsStr(C, N(LandrixXmlFormatDouble(LandrixXmlParseDouble(U(A)), StrToInt(B))),
        'double ' + A + ' with ' + B + ' decimals');
    end;
  finally
    L.Free;
  end;
end;

procedure TestDoubleBitsData;
var
  L: TStringList;
  I: Integer;
  A, B, C: string;
  D: Double;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(DataFile('double-bits.txt'));
    Check(L.Count > 1000, 'double bit cases present');
    for I := 0 to L.Count - 1 do
    begin
      SplitLine(L[I], A, B, C);
      D := LandrixXmlParseDouble(U(A));
      CheckEqualsStr(B, IntToHex(PInt64(@D)^, 16), 'bits of ' + A);
    end;
  finally
    L.Free;
  end;
end;

{ --- Currency --------------------------------------------------------------- }

procedure TestCurrencyParsing;
var
  C: Currency;
begin
  CheckEqualsStr('12.5000', Cur(' 12.5 '), 'white space around');
  CheckEqualsStr('12.5000', Cur(#9#10'+12.5'#13), 'plus sign and XML white space');
  CheckEqualsStr('0.5000', Cur('.5'), 'no integer digits');
  CheckEqualsStr('5.0000', Cur('5.'), 'no fraction digits');
  CheckEqualsStr('0.0000', Cur('-0'), 'negative zero');
  CheckEqualsStr('1.5000', Cur('1.500000000'), 'trailing zeros beyond 4 decimals are exact');
  CheckEqualsStr('7.0000', Cur('0007'), 'leading zeros');
  CheckEqualsStr('922337203685477.5807', Cur('922337203685477.5807'), 'maximum');
  CheckEqualsStr('-922337203685477.5808', Cur('-922337203685477.5808'), 'minimum');
  Bad(0, '', 0, 'empty');
  Bad(0, '   ', 3, 'only white space');
  Bad(0, '12x', 2, 'letter');
  Bad(0, ' 12x', 3, 'offset counts leading white space');
  Bad(0, '1,5', 1, 'comma');
  Bad(0, '1 000', 1, 'inner space');
  Bad(0, '1e5', 1, 'exponent');
  Bad(0, '--1', 1, 'double sign');
  Bad(0, '.', 0, 'only a point');
  Bad(0, '+', 0, 'only a sign');
  Bad(0, '1.2.3', 3, 'two points');
  Bad(0, '0x10', 1, 'hex prefix');
  Bad(0, '$10', 0, 'dollar prefix');
  Bad(0, '922337203685477.5808', -1, 'above maximum');
  Bad(0, '-922337203685477.5809', -1, 'below minimum');
  Bad(0, '99999999999999999999', -1, 'far above maximum');
  Bad(0, '0.00005', 6, 'fifth decimal not zero');
  Bad(0, '1.23451', 6, 'fifth decimal not zero after others');
  { AllowRounding }
  CheckEqualsStr('0.0001', N(LandrixXmlFormatCurrency(LandrixXmlParseCurrency('0.00005', True), 4)),
    'rounding half away from zero');
  CheckEqualsStr('-0.0001', N(LandrixXmlFormatCurrency(LandrixXmlParseCurrency('-0.00005', True), 4)),
    'rounding negative half away from zero');
  CheckEqualsStr('1.2345', N(LandrixXmlFormatCurrency(LandrixXmlParseCurrency('1.234549999', True), 4)),
    'rounding looks at the fifth decimal only');
  CheckEqualsStr('922337203685477.5807', N(LandrixXmlFormatCurrency(
    LandrixXmlParseCurrency('922337203685477.58071', True), 4)), 'rounding down at the maximum');
  Check(not LandrixXmlTryParseCurrency('922337203685477.58075', C, True),
    'rounding up beyond the maximum');
  Check(not LandrixXmlTryParseCurrency('abc', C), 'TryParse fails');
  CheckEqualsStr('0', N(LandrixXmlFormatCurrency(C, 0)), 'TryParse leaves 0 on failure');
  Check(LandrixXmlTryParseCurrencyBuf(PAnsiChar('x19.99y') + 1, 5, C), 'Buf variant');
  CheckEqualsStr('19.99', N(LandrixXmlFormatCurrency(C, 2)), 'Buf variant value');
end;

procedure TestCurrencyFormatting;
var
  C: Currency;
begin
  C := LandrixXmlParseCurrency('1.5');
  CheckEqualsStr('1.50000', N(LandrixXmlFormatCurrency(C, 5)), 'padding beyond 4 decimals');
  CheckEqualsStr('1.500000000000000000', N(LandrixXmlFormatCurrency(C, 18)), '18 decimals');
  CheckEqualsStr('2', N(LandrixXmlFormatCurrency(C, 0)), 'half rounds up');
  CheckEqualsStr('-2', N(LandrixXmlFormatCurrency(LandrixXmlParseCurrency('-1.5'), 0)),
    'negative half rounds away from zero');
  CheckEqualsStr('0.00', N(LandrixXmlFormatCurrency(LandrixXmlParseCurrency('-0.0001'), 2)),
    'no negative zero');
  CheckEqualsStr('1000.00', N(LandrixXmlFormatCurrency(LandrixXmlParseCurrency('999.995'), 2)),
    'carry into a new digit');
  CheckEqualsStr('1.5', N(LandrixXmlFormatCurrencyTrim(C, 0, 4)), 'trim');
  CheckEqualsStr('1.50', N(LandrixXmlFormatCurrencyTrim(C, 2, 4)), 'trim down to MinDecimals');
  CheckEqualsStr('2', N(LandrixXmlFormatCurrencyTrim(LandrixXmlParseCurrency('2.0000'), 0, 4)),
    'trim the point');
  CheckEqualsStr('1.235', N(LandrixXmlFormatCurrencyTrim(LandrixXmlParseCurrency('1.2345'), 0, 3)),
    'trim after rounding');
  CheckEqualsStr('-922337203685477.5808', N(LandrixXmlFormatCurrency(
    LandrixXmlParseCurrency('-922337203685477.5808'), 4)), 'minimum');
  CheckEqualsStr('-922337203685478', N(LandrixXmlFormatCurrency(
    LandrixXmlParseCurrency('-922337203685477.5808'), 0)), 'minimum rounded (text beyond range)');
  ExpectArgError(0, 'negative decimals');
  ExpectArgError(1, 'more than 18 decimals');
  ExpectArgError(2, 'MinDecimals above MaxDecimals');
end;

{ --- Double ----------------------------------------------------------------- }

procedure TestDouble;
var
  D: Double;
begin
  D := LandrixXmlParseDouble('-0');
  CheckEqualsStr('0000000000000000', IntToHex(PInt64(@D)^, 16), '-0 parses as +0');
  D := LandrixXmlParseDouble(' 0.12345678901234567890123 ');
  Check(Abs(D - Dbl('0.123456789012345678')) < Dbl('0.000000000000001'),
    'long mantissa via the RTL');
  D := LandrixXmlParseDouble('12345678901234567890');
  Check(Abs(D - Dbl('12345678901234567000')) < 10000, 'long integer via the RTL');
  Bad(1, '1e5', 1, 'exponent');
  Bad(1, 'INF', 0, 'INF');
  Bad(1, 'NaN', 0, 'NaN');
  Bad(1, '1,5', 1, 'comma');
  Bad(1, '1' + StringOfChar('0', 400), -1, 'too large');
  Bad(1, '18' + StringOfChar('0', 307), -1, 'above the largest double');
  Bad(1, '17976931348623159' + StringOfChar('0', 292), -1, 'just above the largest double');
  { more than 15 digits go through the RTL (may be off by one ulp) }
  Bad(1, '17976931348623157' + StringOfChar('0', 292), -1,
    'within 15 ulps of the largest double: conservatively out of range');
  D := LandrixXmlParseDouble(U('17976931348623' + StringOfChar('0', 295)));
  CheckEqualsStr('7FE', IntToHex((PInt64(@D)^ shr 52) and $FFF, 3), 'near the largest double');
  D := LandrixXmlParseDouble(U('0.' + StringOfChar('7', 600)));
  Check(Abs(D - Dbl('0.7777777777777777')) < Dbl('0.0000000000000002'),
    'very long mantissa (more than 255 characters)');
  D := LandrixXmlParseDouble(U('0.' + StringOfChar('0', 400) + '1'));
  CheckEqualsStr('0000000000000000', IntToHex(PInt64(@D)^, 16), 'underflow to zero');
  CheckEqualsStr('1000000000000000000000.00', N(LandrixXmlFormatDouble(Dbl('1' +
    StringOfChar('0', 21)), 2)), '1e21');
  CheckEqualsStr('123456789012346000.00', N(LandrixXmlFormatDouble(Dbl('123456789012345678'), 2)),
    '15 significant digits above 1e15');
  CheckEqualsStr('2.68', N(LandrixXmlFormatDouble(2.675, 2)), '2.675 as written');
  CheckEqualsStr('1.01', N(LandrixXmlFormatDouble(1.005, 2)), '1.005 as written');
  CheckEqualsStr('-0.13', N(LandrixXmlFormatDouble(-0.125, 2)), 'negative half');
  CheckEqualsStr('0.00', N(LandrixXmlFormatDouble(-0.001, 2)), 'no negative zero');
  CheckEqualsStr('0', N(LandrixXmlFormatDouble(0, 0)), 'zero');
  CheckEqualsStr('1000000000000000.00', N(LandrixXmlFormatDouble(1E15, 2)), '1e15');
  CheckEqualsStr('0.000001', N(LandrixXmlFormatDouble(Dbl('0.000001'), 6)), 'small value');
  CheckEqualsStr('0.1', N(LandrixXmlFormatDoubleTrim(0.1, 0, 6)), 'trim');
  CheckEqualsStr('3', N(LandrixXmlFormatDoubleTrim(3, 0, 6)), 'trim to integer');
  ExpectArgError(3, 'NaN');
end;

{ --- integers and booleans ------------------------------------------------- }

procedure TestIntegersAndBooleans;
var
  I: Integer;
  B: Boolean;
  V: Int64;
begin
  CheckEqualsStr('9223372036854775807', N(LandrixXmlFormatInt64(LandrixXmlParseInt64('9223372036854775807'))),
    'Int64 maximum');
  CheckEqualsStr('-9223372036854775808', N(LandrixXmlFormatInt64(LandrixXmlParseInt64('-9223372036854775808'))),
    'Int64 minimum');
  CheckEqualsStr('5', N(LandrixXmlFormatInt64(LandrixXmlParseInt64(' +5 '))), 'plus and white space');
  CheckEqualsStr('0', N(LandrixXmlFormatInt64(LandrixXmlParseInt64('-000'))), 'negative zero');
  Bad(2, '9223372036854775808', 0, 'Int64 overflow');
  Bad(2, '-9223372036854775809', 0, 'Int64 underflow');
  Bad(2, '0x10', 1, 'hex prefix');
  Bad(2, '$10', 0, 'dollar');
  Bad(2, '1.0', 1, 'decimal point');
  Bad(2, '-', 0, 'only a sign');
  Bad(2, '', 0, 'empty');
  Bad(2, '1 2', 1, 'inner space');
  CheckEquals(-2147483647 - 1, LandrixXmlParseInteger('-2147483648'), 'Integer minimum');
  CheckEquals(2147483647, LandrixXmlParseInteger('2147483647'), 'Integer maximum');
  Bad(3, '2147483648', 0, 'Integer overflow');
  Bad(3, ' 2147483648', 1, 'Integer overflow after white space');
  CheckEquals(12, LandrixXmlParseIntegerBuf(PAnsiChar('123'), 2), 'Buf variant stops at Len');
  CheckEquals(Ord(True), Ord(LandrixXmlParseBooleanBuf(PAnsiChar('1x'), 1)), 'Boolean Buf variant');
  Check(not LandrixXmlTryParseInteger('x', I) and (I = 0), 'TryParseInteger');
  Check(not LandrixXmlTryParseInt64('x', V) and (V = 0), 'TryParseInt64');

  Check(LandrixXmlParseBoolean('true'), 'true');
  Check(not LandrixXmlParseBoolean('false'), 'false');
  Check(LandrixXmlParseBoolean(' 1 '), '1');
  Check(not LandrixXmlParseBoolean('0'), '0');
  Bad(4, 'TRUE', 0, 'upper case');
  Bad(4, 'yes', 0, 'yes');
  Bad(4, '', 0, 'empty boolean');
  Check(not LandrixXmlTryParseBoolean('x', B) and not B, 'TryParseBoolean');
  CheckEqualsStr('true', N(LandrixXmlFormatBoolean(True)), 'format true');
  CheckEqualsStr('false', N(LandrixXmlFormatBoolean(False)), 'format false');
end;

{ --- dates ------------------------------------------------------------------- }

function PartsStr(const P: TLandrixXmlDateTime): string;
begin
  Result := Format('%d-%d-%d %d:%d:%d.%d', [P.Year, P.Month, P.Day, P.Hour, P.Minute,
    P.Second, P.Millisecond]);
  if P.HasTimeZone then
    Result := Result + ' tz' + IntToStr(P.TimeZoneMinutes);
end;

procedure TestDates;
var
  P: TLandrixXmlDateTime;
  D: TDateTime;
begin
  CheckEqualsStr('2024-1-31 0:0:0.0', PartsStr(LandrixXmlParseDateParts('2024-01-31')), 'date');
  CheckEqualsStr('2024-1-31 0:0:0.0', PartsStr(LandrixXmlParseDatePartsBuf(
    PAnsiChar('2024-01-31T10:00:00'), 10)), 'Buf variant stops at Len');
  CheckEqualsStr('2024-2-29 0:0:0.0', PartsStr(LandrixXmlParseDateParts(' 2024-02-29 ')), 'leap day');
  CheckEqualsStr('2024-1-31 0:0:0.0 tz0', PartsStr(LandrixXmlParseDateParts('2024-01-31Z')), 'Z');
  CheckEqualsStr('2024-1-31 0:0:0.0 tz60', PartsStr(LandrixXmlParseDateParts('2024-01-31+01:00')),
    'positive zone');
  CheckEqualsStr('2024-1-31 0:0:0.0 tz-840', PartsStr(LandrixXmlParseDateParts('2024-01-31-14:00')),
    'zone -14:00');
  Bad(5, '2023-02-29', 0, 'no leap year');
  Bad(5, '1900-02-29', 0, '1900 is no leap year');
  CheckEqualsStr('2000-2-29 0:0:0.0', PartsStr(LandrixXmlParseDateParts('2000-02-29')), '2000 is');
  Bad(5, '2024-13-01', 0, 'month 13');
  Bad(5, '2024-04-31', 0, 'April 31');
  Bad(5, '0000-01-01', 0, 'year 0');
  Bad(5, '10000-01-01', 0, 'year 10000');
  Bad(5, '-2024-01-01', 0, 'negative year');
  Bad(5, '2024-1-01', 5, 'one-digit month');
  Bad(5, '2024-01-31+14:01', 10, 'zone beyond 14:00');
  Bad(5, '2024-01-31+01:60', 10, 'zone minutes');
  Bad(5, '2024-01-31Z+01:00', 11, 'two zones');
  Bad(5, '2024/01/31', 4, 'slashes');
  Bad(5, '', 0, 'empty date');

  CheckEqualsStr('2024-1-31 23:59:59.123', PartsStr(LandrixXmlParseDateTimeParts(
    '2024-01-31T23:59:59.1239999')), 'fraction truncated to milliseconds');
  CheckEqualsStr('2024-1-31 8:5:3.500 tz-330', PartsStr(LandrixXmlParseDateTimeParts(
    '2024-01-31T08:05:03.5-05:30')), 'fraction and zone');
  CheckEqualsStr('2025-1-1 0:0:0.0', PartsStr(LandrixXmlParseDateTimeParts(
    '2024-12-31T24:00:00')), '24:00:00 is the next day');
  CheckEqualsStr('2024-3-1 0:0:0.0', PartsStr(LandrixXmlParseDateTimeParts(
    '2024-02-29T24:00:00.000')), '24:00 at the end of February');
  Bad(6, '9999-12-31T24:00:00', 0, '24:00 after 9999-12-31');
  Bad(6, '2024-01-31T24:00:01', 11, '24:00:01');
  Bad(6, '2024-01-31T24:00:00.1', 11, '24:00:00.1');
  Bad(6, '2024-01-31T23:60:00', 11, 'minute 60');
  Bad(6, '2024-01-31T23:59:60', 11, 'leap second');
  Bad(6, '2024-01-31T12:00', 16, 'no seconds');
  Bad(6, '2024-01-31 12:00:00', 10, 'space instead of T');
  Bad(6, '2024-01-31T12:00:00.', 20, 'point without digits');
  Bad(6, '2024-01-31', 10, 'date only');

  CheckEqualsStr('0-0-0 12:30:0.0', PartsStr(LandrixXmlParseTimeParts('12:30:00')), 'time');
  CheckEqualsStr('0-0-0 0:0:0.0 tz0', PartsStr(LandrixXmlParseTimeParts('24:00:00Z')), 'time 24:00');
  Bad(7, '25:00:00', 0, 'hour 25');

  { TDateTime convenience }
  D := LandrixXmlParseDateTime('2024-01-31T08:05:03.007+01:00');
  Check(Abs(D - (EncodeDate(2024, 1, 31) + EncodeTime(8, 5, 3, 7))) < Dbl('0.000000001'),
    'TDateTime as written, zone ignored');
  CheckEqualsStr('2024-01-31T08:05:03.007', N(LandrixXmlFormatDateTime(D)), 'format with ms');
  CheckEqualsStr('2024-01-31', N(LandrixXmlFormatDate(D)), 'format date');
  CheckEqualsStr('08:05:03.007', N(LandrixXmlFormatTime(D)), 'format time');
  CheckEqualsStr('2024-01-31T08:05:03.007+01:00', N(LandrixXmlFormatDateTimeTz(D, 60)), 'zone +01:00');
  CheckEqualsStr('2024-01-31T08:05:03.007Z', N(LandrixXmlFormatDateTimeTz(D, 0)), 'zone Z');
  CheckEqualsStr('2024-01-31T08:05:03.007-05:30', N(LandrixXmlFormatDateTimeTz(D, -330)), 'zone -05:30');
  CheckEqualsStr('2024-01-31T00:00:00', N(LandrixXmlFormatDateTime(LandrixXmlParseDate('2024-01-31'))),
    'no milliseconds when 0');
  D := LandrixXmlParseDateTime('1800-01-01T06:00:00');
  CheckEqualsStr('1800-01-01T06:00:00', N(LandrixXmlFormatDateTime(D)), 'before 1899-12-30');
  D := LandrixXmlParseDateTime('0001-01-01T00:00:00');
  CheckEqualsStr('0001-01-01T00:00:00', N(LandrixXmlFormatDateTime(D)), 'year 1');
  D := LandrixXmlParseDateTime('9999-12-31T23:59:59.999');
  CheckEqualsStr('9999-12-31T23:59:59.999', N(LandrixXmlFormatDateTime(D)), 'year 9999');
  D := LandrixXmlParseTime('18:30:15');
  Check(Abs(D - EncodeTime(18, 30, 15, 0)) < Dbl('0.000000001'), 'time as day fraction');
  Check(not LandrixXmlTryParseDate('2024-02-30', D) and (D = 0), 'TryParseDate');
  ExpectArgError(4, 'zone beyond 14 hours');

  { parts formatting }
  P := LandrixXmlParseDateTimeParts('2024-01-31T08:05:03Z');
  CheckEqualsStr('2024-01-31T08:05:03Z', N(LandrixXmlFormatDateTimeParts(P)), 'parts round trip');
  CheckEqualsStr('2024-01-31Z', N(LandrixXmlFormatDateParts(P)), 'date parts with zone');
  CheckEqualsStr('08:05:03Z', N(LandrixXmlFormatTimeParts(P)), 'time parts with zone');
end;

procedure TestCiiDates;
var
  P: TLandrixXmlDateTime;
  D: TDateTime;
begin
  CheckEqualsStr('2024-1-31 0:0:0.0', PartsStr(LandrixXmlParseCiiDateParts('20240131', 102)), '102');
  CheckEqualsStr('2024-1-0 0:0:0.0', PartsStr(LandrixXmlParseCiiDateParts(' 202401 ', 610)), '610');
  Bad(8, '2024013', 7, 'too short');
  Bad(8, '202401310', 8, 'too long');
  Bad(8, '20240230', 0, 'February 30');
  Bad(8, '2024-01-31', 4, 'xs:date is not format 102');
  Bad(9, '202413', 0, 'month 13 in 610');
  try
    LandrixXmlTryParseCiiDateParts('20240131', 616, P);
    FailNotRaised('ELandrixXmlError for format 616');
  except
    on E: ELandrixXmlError do
      CheckEquals(Ord(xecInvalidArgument), Ord(E.Code), 'format 616 is not supported yet');
  end;
  D := LandrixXmlParseCiiDate('20240131');
  CheckEqualsStr('20240131', N(LandrixXmlFormatCiiDate(D)), 'format 102');
  CheckEqualsStr('202401', N(LandrixXmlFormatCiiDate(D, 610)), 'format 610');
  ExpectArgError(5, 'format 616');
end;

{ --- base64 decoding ------------------------------------------------------ }

function Decode(const S: AnsiString): AnsiString;
var
  Buf: TLandrixXmlBuffer;
begin
  Buf := TLandrixXmlBuffer.Create;
  try
    LandrixXmlBase64Decode(PAnsiChar(S), Length(S), Buf);
    SetString(Result, Buf.Data, Buf.Size);
  finally
    Buf.Free;
  end;
end;

procedure BadBase64(const S: AnsiString; Offset: Integer; const Name: string);
var
  Buf: TLandrixXmlBuffer;
begin
  Buf := TLandrixXmlBuffer.Create;
  try
    Buf.AppendByte(Ord('x'));
    try
      LandrixXmlBase64Decode(PAnsiChar(S), Length(S), Buf);
      FailNotRaised('ELandrixXmlError for ' + Name);
    except
      on E: ELandrixXmlError do
      begin
        CheckEquals(Ord(xecConversion), Ord(E.Code), Name + ' (code)');
        CheckEqualsInt64(Offset, E.Offset, Name + ' (offset; message: ' + E.Message + ')');
      end;
    end;
    CheckEquals(1, Buf.Size, Name + ' (destination unchanged)');
  finally
    Buf.Free;
  end;
end;

procedure TestBase64Decode;
var
  Data, Encoded: AnsiString;
  Buf: TLandrixXmlBuffer;
  M: TMemoryStream;
  I, Size, Bad: Integer;
begin
  CheckEqualsBytes('', Decode(''), 'empty');
  CheckEqualsBytes('f', Decode('Zg=='), 'f');
  CheckEqualsBytes('fo', Decode('Zm8='), 'fo');
  CheckEqualsBytes('foo', Decode('Zm9v'), 'foo');
  CheckEqualsBytes('foobar', Decode('Zm9vYmFy'), 'foobar');
  CheckEqualsBytes('foobar', Decode(' Zm9v'#13#10'Ym Fy'#9), 'white space anywhere');
  CheckEqualsBytes(Bytes([$00, $FF, $FE]), Decode('AP/+'), 'high bytes');
  BadBase64('Zg=', 3, 'truncated group');
  BadBase64('Zm9', 3, 'missing padding');
  BadBase64('Z===', 1, 'padding too early');
  BadBase64('Zh==', 1, 'non-zero pad bits (2 symbols)');
  BadBase64('Zm9=', 2, 'non-zero pad bits (3 symbols)');
  BadBase64('Zg==Zg==', 4, 'data after padding');
  BadBase64('Zg=a', 3, 'symbol after padding');
  BadBase64('!!!!', 0, 'invalid symbol');
  BadBase64('Zm9v-_', 4, 'base64url symbols');
  Check(LandrixXmlValidateBase64Buf(PAnsiChar('Zm9vYg== '), 9, Size, Bad) and (Size = 4) and
    (Bad = -1), 'validate: decoded size');
  Check(not LandrixXmlValidateBase64Buf(PAnsiChar('Zm9vY'), 5, Size, Bad) and (Bad = 5) and
    (Size = 0), 'validate: truncated group reports Len');

  { large data through the stream decoder }
  Data := '';
  SetLength(Data, 200003);
  for I := 1 to Length(Data) do
    Data[I] := AnsiChar((I * 7) mod 256);
  Buf := TLandrixXmlBuffer.Create;
  M := TMemoryStream.Create;
  try
    LandrixXmlBase64Encode(PAnsiChar(Data)^, Length(Data), Buf);
    SetString(Encoded, Buf.Data, Buf.Size);
    LandrixXmlBase64DecodeToStream(PAnsiChar(Encoded), Length(Encoded), M);
    CheckEqualsInt64(Length(Data), M.Size, 'stream size');
    Check(SameMemory(M.Memory, PAnsiChar(Data), Length(Data)), 'stream content');
    M.Clear;
    try
      LandrixXmlBase64DecodeToStream(PAnsiChar(Encoded + '!'), Length(Encoded) + 1, M);
      FailNotRaised('ELandrixXmlError for a bad stream input');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecConversion), Ord(E.Code), 'bad stream input');
    end;
    CheckEqualsInt64(0, M.Size, 'nothing written before the input was checked');
  finally
    M.Free;
    Buf.Free;
  end;
end;

{ --- locale independence --------------------------------------------------- }

type
  TLocaleState = record
    Decimal, Thousand, DateSep, TimeSep: Char;
    ShortDate: string;
  end;

procedure GetLocale(out S: TLocaleState);
begin
{$IFDEF FPC}
  S.Decimal := DefaultFormatSettings.DecimalSeparator;
  S.Thousand := DefaultFormatSettings.ThousandSeparator;
  S.DateSep := DefaultFormatSettings.DateSeparator;
  S.TimeSep := DefaultFormatSettings.TimeSeparator;
  S.ShortDate := DefaultFormatSettings.ShortDateFormat;
{$ELSE}
  {$IF CompilerVersion >= 22.0}
  S.Decimal := FormatSettings.DecimalSeparator;
  S.Thousand := FormatSettings.ThousandSeparator;
  S.DateSep := FormatSettings.DateSeparator;
  S.TimeSep := FormatSettings.TimeSeparator;
  S.ShortDate := FormatSettings.ShortDateFormat;
  {$ELSE}
  S.Decimal := DecimalSeparator;
  S.Thousand := ThousandSeparator;
  S.DateSep := DateSeparator;
  S.TimeSep := TimeSeparator;
  S.ShortDate := ShortDateFormat;
  {$IFEND}
{$ENDIF}
end;

procedure SetLocale(const S: TLocaleState);
begin
{$IFDEF FPC}
  DefaultFormatSettings.DecimalSeparator := S.Decimal;
  DefaultFormatSettings.ThousandSeparator := S.Thousand;
  DefaultFormatSettings.DateSeparator := S.DateSep;
  DefaultFormatSettings.TimeSeparator := S.TimeSep;
  DefaultFormatSettings.ShortDateFormat := S.ShortDate;
{$ELSE}
  {$IF CompilerVersion >= 22.0}
  FormatSettings.DecimalSeparator := S.Decimal;
  FormatSettings.ThousandSeparator := S.Thousand;
  FormatSettings.DateSeparator := S.DateSep;
  FormatSettings.TimeSeparator := S.TimeSep;
  FormatSettings.ShortDateFormat := S.ShortDate;
  {$ELSE}
  DecimalSeparator := S.Decimal;
  ThousandSeparator := S.Thousand;
  DateSeparator := S.DateSep;
  TimeSeparator := S.TimeSep;
  ShortDateFormat := S.ShortDate;
  {$IFEND}
{$ENDIF}
end;

procedure TestLocaleIndependence;
var
  Saved, German: TLocaleState;
  D: TDateTime;
begin
  GetLocale(Saved);
  German.Decimal := ',';
  German.Thousand := '.';
  German.DateSep := '.';
  German.TimeSep := '-';
  German.ShortDate := 'dd.mm.yy';
  SetLocale(German);
  try
    CheckEqualsStr('1234.57', N(LandrixXmlFormatCurrency(LandrixXmlParseCurrency('1234.565'), 2)),
      'currency');
    CheckEqualsStr('2.68', N(LandrixXmlFormatDouble(LandrixXmlParseDouble('2.675'), 2)), 'double');
    CheckEqualsStr('0.12345678901234600', N(LandrixXmlFormatDouble(
      LandrixXmlParseDouble('0.12345678901234567890'), 17)), 'double through the RTL path');
    Bad(0, '1,5', 1, 'comma stays invalid');
    D := LandrixXmlParseDateTime('2024-01-31T08:05:03');
    CheckEqualsStr('2024-01-31T08:05:03', N(LandrixXmlFormatDateTime(D)), 'date time');
    CheckEqualsStr('20240131', N(LandrixXmlFormatCiiDate(D)), 'CII date');
  finally
    SetLocale(Saved);
  end;
end;

procedure Register;
begin
  RegisterTest('Convert.CurrencyData', TestCurrencyData);
  RegisterTest('Convert.DoubleFormatData', TestDoubleFormatData);
  RegisterTest('Convert.DoubleBitsData', TestDoubleBitsData);
  RegisterTest('Convert.CurrencyParsing', TestCurrencyParsing);
  RegisterTest('Convert.CurrencyFormatting', TestCurrencyFormatting);
  RegisterTest('Convert.Double', TestDouble);
  RegisterTest('Convert.IntegersAndBooleans', TestIntegersAndBooleans);
  RegisterTest('Convert.Dates', TestDates);
  RegisterTest('Convert.CiiDates', TestCiiDates);
  RegisterTest('Convert.Base64Decode', TestBase64Decode);
  RegisterTest('Convert.LocaleIndependence', TestLocaleIndependence);
end;

end.
