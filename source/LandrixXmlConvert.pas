{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Locale-independent conversion between XML Schema lexical forms and
  Pascal values: xs:decimal (Currency, Double), xs:long/xs:int (Int64,
  Integer), xs:boolean, xs:date, xs:dateTime, xs:time and the UN/CEFACT
  CII date formats 102 (YYYYMMDD) and 610 (YYYYMM).

  For every type there is
    LandrixXmlFormatX       value -> TLandrixXmlUtf8
    LandrixXmlParseX        TLandrixXmlUtf8 -> value, raises ELandrixXmlError
                            (Code = xecConversion, Offset = byte position
                            in the value)
    LandrixXmlTryParseX     returns False instead of raising (the output is
                            then 0 / False / all zero)
  and ...Buf variants taking a pointer and a length, e.g. for
  TLandrixXmlReader.ValueSpan without copying.

  Rules (see PLAN.md decision log):
  - Nothing depends on DecimalSeparator, date formats or other locale
    settings, and the RTL number conversions (Val, Str, Round) are not
    used where their results differ between compilers. Currency is
    handled through its scaled 64-bit integer.
  - Parsing accepts the xs:decimal form only: optional sign, digits, at
    most one '.', XML white space around the value. No exponent, no
    thousands separators, no ','.
  - Currency parsing is exact: a non-zero digit after the fourth decimal is
    an error unless AllowRounding is True.
  - Rounding is half away from zero (commercial rounding). Double values
    are rounded as written: first to 15 significant digits, then
    decimally, so 2.675 becomes 2.68. Values with more than 15 significant
    digits may differ in the last digit between compilers.
  - Double parsing is exact (correctly rounded) for up to 15 significant
    digits; longer mantissas use the RTL and may differ by one unit in the
    last place between compilers.
  - Dates are returned as written; time zones are reported, never applied.
    Years 0001-9999, full calendar check, time zones up to +-14:00,
    24:00:00 means 00:00:00 of the next day, fraction digits beyond
    milliseconds are truncated. }

unit LandrixXmlConvert;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  LandrixXmlBase;

type
  { Date and time as written. Unused parts are 0: Day for CII format 610,
    Year/Month/Day for xs:time, the time parts for xs:date. }
  TLandrixXmlDateTime = record
    Year: Integer;
    Month: Integer;
    Day: Integer;
    Hour: Integer;
    Minute: Integer;
    Second: Integer;
    Millisecond: Integer;
    HasTimeZone: Boolean;
    { offset from UTC in minutes, -840..840; 0 with HasTimeZone = 'Z' }
    TimeZoneMinutes: Integer;
  end;

{ --- Currency (xs:decimal with up to 4 decimals) ------------------------ }

function LandrixXmlTryParseCurrencyBuf(P: PAnsiChar; Len: Integer; out Value: Currency;
  AllowRounding: Boolean = False): Boolean;
function LandrixXmlTryParseCurrency(const S: TLandrixXmlUtf8; out Value: Currency;
  AllowRounding: Boolean = False): Boolean;
function LandrixXmlParseCurrencyBuf(P: PAnsiChar; Len: Integer;
  AllowRounding: Boolean = False): Currency;
function LandrixXmlParseCurrency(const S: TLandrixXmlUtf8;
  AllowRounding: Boolean = False): Currency;
{ Exactly Decimals (0..18) decimals, rounded half away from zero. }
function LandrixXmlFormatCurrency(Value: Currency; Decimals: Integer): TLandrixXmlUtf8;
{ Rounded to MaxDecimals, then trailing zeros removed down to MinDecimals
  (1.5000 with 0..4 gives 1.5). }
function LandrixXmlFormatCurrencyTrim(Value: Currency;
  MinDecimals, MaxDecimals: Integer): TLandrixXmlUtf8;

{ --- Double (xs:decimal) ------------------------------------------------ }

function LandrixXmlTryParseDoubleBuf(P: PAnsiChar; Len: Integer; out Value: Double): Boolean;
function LandrixXmlTryParseDouble(const S: TLandrixXmlUtf8; out Value: Double): Boolean;
function LandrixXmlParseDoubleBuf(P: PAnsiChar; Len: Integer): Double;
function LandrixXmlParseDouble(const S: TLandrixXmlUtf8): Double;
{ Exactly Decimals (0..18) decimals; NaN, infinities and values of 1e23
  and above raise xecInvalidArgument. }
function LandrixXmlFormatDouble(Value: Double; Decimals: Integer): TLandrixXmlUtf8;
function LandrixXmlFormatDoubleTrim(Value: Double;
  MinDecimals, MaxDecimals: Integer): TLandrixXmlUtf8;

{ --- Integers ----------------------------------------------------------- }

function LandrixXmlTryParseInt64Buf(P: PAnsiChar; Len: Integer; out Value: Int64): Boolean;
function LandrixXmlTryParseInt64(const S: TLandrixXmlUtf8; out Value: Int64): Boolean;
function LandrixXmlParseInt64Buf(P: PAnsiChar; Len: Integer): Int64;
function LandrixXmlParseInt64(const S: TLandrixXmlUtf8): Int64;
function LandrixXmlTryParseIntegerBuf(P: PAnsiChar; Len: Integer; out Value: Integer): Boolean;
function LandrixXmlTryParseInteger(const S: TLandrixXmlUtf8; out Value: Integer): Boolean;
function LandrixXmlParseIntegerBuf(P: PAnsiChar; Len: Integer): Integer;
function LandrixXmlParseInteger(const S: TLandrixXmlUtf8): Integer;
function LandrixXmlFormatInt64(Value: Int64): TLandrixXmlUtf8;

{ --- Boolean (true, false, 1, 0) ----------------------------------------- }

function LandrixXmlTryParseBooleanBuf(P: PAnsiChar; Len: Integer; out Value: Boolean): Boolean;
function LandrixXmlTryParseBoolean(const S: TLandrixXmlUtf8; out Value: Boolean): Boolean;
function LandrixXmlParseBooleanBuf(P: PAnsiChar; Len: Integer): Boolean;
function LandrixXmlParseBoolean(const S: TLandrixXmlUtf8): Boolean;
function LandrixXmlFormatBoolean(Value: Boolean): TLandrixXmlUtf8;

{ --- Date and time: parts as written ------------------------------------- }

function LandrixXmlTryParseDatePartsBuf(P: PAnsiChar; Len: Integer;
  out Value: TLandrixXmlDateTime): Boolean;
function LandrixXmlTryParseDateParts(const S: TLandrixXmlUtf8;
  out Value: TLandrixXmlDateTime): Boolean;
function LandrixXmlParseDatePartsBuf(P: PAnsiChar; Len: Integer): TLandrixXmlDateTime;
function LandrixXmlParseDateParts(const S: TLandrixXmlUtf8): TLandrixXmlDateTime;

function LandrixXmlTryParseDateTimePartsBuf(P: PAnsiChar; Len: Integer;
  out Value: TLandrixXmlDateTime): Boolean;
function LandrixXmlTryParseDateTimeParts(const S: TLandrixXmlUtf8;
  out Value: TLandrixXmlDateTime): Boolean;
function LandrixXmlParseDateTimePartsBuf(P: PAnsiChar; Len: Integer): TLandrixXmlDateTime;
function LandrixXmlParseDateTimeParts(const S: TLandrixXmlUtf8): TLandrixXmlDateTime;

function LandrixXmlTryParseTimePartsBuf(P: PAnsiChar; Len: Integer;
  out Value: TLandrixXmlDateTime): Boolean;
function LandrixXmlTryParseTimeParts(const S: TLandrixXmlUtf8;
  out Value: TLandrixXmlDateTime): Boolean;
function LandrixXmlParseTimePartsBuf(P: PAnsiChar; Len: Integer): TLandrixXmlDateTime;
function LandrixXmlParseTimeParts(const S: TLandrixXmlUtf8): TLandrixXmlDateTime;

{ Formatting from parts (the parts are checked; invalid parts raise
  xecInvalidArgument). The time zone is written when HasTimeZone is set. }
function LandrixXmlFormatDateParts(const Value: TLandrixXmlDateTime): TLandrixXmlUtf8;
function LandrixXmlFormatDateTimeParts(const Value: TLandrixXmlDateTime): TLandrixXmlUtf8;
function LandrixXmlFormatTimeParts(const Value: TLandrixXmlDateTime): TLandrixXmlUtf8;

{ Parts -> TDateTime (time zone ignored) and back. }
function LandrixXmlPartsToDateTime(const Value: TLandrixXmlDateTime): TDateTime;
function LandrixXmlDateTimeToParts(Value: TDateTime): TLandrixXmlDateTime;

{ --- Date and time: TDateTime as written (time zone ignored) ------------ }

function LandrixXmlTryParseDateBuf(P: PAnsiChar; Len: Integer; out Value: TDateTime): Boolean;
function LandrixXmlTryParseDate(const S: TLandrixXmlUtf8; out Value: TDateTime): Boolean;
function LandrixXmlParseDateBuf(P: PAnsiChar; Len: Integer): TDateTime;
function LandrixXmlParseDate(const S: TLandrixXmlUtf8): TDateTime;

function LandrixXmlTryParseDateTimeBuf(P: PAnsiChar; Len: Integer; out Value: TDateTime): Boolean;
function LandrixXmlTryParseDateTime(const S: TLandrixXmlUtf8; out Value: TDateTime): Boolean;
function LandrixXmlParseDateTimeBuf(P: PAnsiChar; Len: Integer): TDateTime;
function LandrixXmlParseDateTime(const S: TLandrixXmlUtf8): TDateTime;

{ Time of day as a TDateTime fraction (0 <= Value < 1). }
function LandrixXmlTryParseTimeBuf(P: PAnsiChar; Len: Integer; out Value: TDateTime): Boolean;
function LandrixXmlTryParseTime(const S: TLandrixXmlUtf8; out Value: TDateTime): Boolean;
function LandrixXmlParseTimeBuf(P: PAnsiChar; Len: Integer): TDateTime;
function LandrixXmlParseTime(const S: TLandrixXmlUtf8): TDateTime;

{ YYYY-MM-DD }
function LandrixXmlFormatDate(Value: TDateTime): TLandrixXmlUtf8;
{ YYYY-MM-DDThh:mm:ss, with .fff only when the milliseconds are not 0 }
function LandrixXmlFormatDateTime(Value: TDateTime): TLandrixXmlUtf8;
{ Same plus a time zone: Z for 0, else +hh:mm / -hh:mm (-840..840). }
function LandrixXmlFormatDateTimeTz(Value: TDateTime; TimeZoneMinutes: Integer): TLandrixXmlUtf8;
{ hh:mm:ss[.fff] of the time of day }
function LandrixXmlFormatTime(Value: TDateTime): TLandrixXmlUtf8;

{ --- CII date formats (udt:DateTimeString/@format) ---------------------- }

{ Format 102 (YYYYMMDD) or 610 (YYYYMM, Day = 0). Other format numbers
  raise xecInvalidArgument (also in the Try variants). }
function LandrixXmlTryParseCiiDatePartsBuf(P: PAnsiChar; Len: Integer; Format: Integer;
  out Value: TLandrixXmlDateTime): Boolean;
function LandrixXmlTryParseCiiDateParts(const S: TLandrixXmlUtf8; Format: Integer;
  out Value: TLandrixXmlDateTime): Boolean;
function LandrixXmlParseCiiDatePartsBuf(P: PAnsiChar; Len: Integer;
  Format: Integer): TLandrixXmlDateTime;
function LandrixXmlParseCiiDateParts(const S: TLandrixXmlUtf8;
  Format: Integer): TLandrixXmlDateTime;
{ Format 102 only. }
function LandrixXmlTryParseCiiDateBuf(P: PAnsiChar; Len: Integer; out Value: TDateTime): Boolean;
function LandrixXmlTryParseCiiDate(const S: TLandrixXmlUtf8; out Value: TDateTime): Boolean;
function LandrixXmlParseCiiDateBuf(P: PAnsiChar; Len: Integer): TDateTime;
function LandrixXmlParseCiiDate(const S: TLandrixXmlUtf8): TDateTime;
{ Format 102 or 610. }
function LandrixXmlFormatCiiDate(Value: TDateTime; Format: Integer = 102): TLandrixXmlUtf8;

implementation

const
  { Low(Int64) div 10; Low(Int64) = MinDiv10 * 10 - 8. Bounds are checked
    without arithmetic on Low(Int64), which FPC's overflow checking
    rejects even when the result fits. }
  MinDiv10 = -922337203685477580;

  { error reasons }
  erSyntax = 0;
  erRange = 1;
  erPrecision = 2;
  erDate = 3;

{ --- helpers ---------------------------------------------------------------- }

{ A * 10 without a multiplication: Delphi 6 raises a false EIntOverflow
  for Int64 products near Low(Int64) under $Q+. Callers check the bounds. }
function Times10(A: Int64): Int64;
begin
  Result := (A shl 3) + (A shl 1);
end;

function ToUtf8(const A: AnsiString): TLandrixXmlUtf8;
begin
  Result := '';
  if A <> '' then
  begin
    SetLength(Result, Length(A));
    Move(PAnsiChar(A)^, PAnsiChar(Result)^, Length(A));
  end;
end;

function IsSpace(C: AnsiChar): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13);
end;

function IsDigit(C: AnsiChar): Boolean;
begin
  Result := (C >= '0') and (C <= '9');
end;

{ Trims XML white space: [S, E) is the remaining range. }
procedure TrimRange(P: PAnsiChar; Len: Integer; out S, E: Integer);
begin
  if Len < 0 then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'Negative length');
  S := 0;
  E := Len;
  while (S < E) and IsSpace(P[S]) do
    Inc(S);
  while (E > S) and IsSpace(P[E - 1]) do
    Dec(E);
end;

procedure RaiseConversion(const TypeName: string; P: PAnsiChar; Len: Integer;
  Offset, Reason: Integer);
var
  Shown: TLandrixXmlUtf8;
  N: Integer;
  Msg: string;
begin
  N := Len;
  if N > 60 then
    N := 60;
  Shown := '';
  if N > 0 then
  begin
    SetLength(Shown, N);
    Move(P^, PAnsiChar(Shown)^, N);
  end;
  case Reason of
    erRange: Msg := 'Value out of range for ' + TypeName;
    erPrecision: Msg := 'Too many decimals for ' + TypeName;
    erDate: Msg := 'Invalid date or time for ' + TypeName;
  else
    Msg := 'Invalid ' + TypeName + ' value';
  end;
  if Len = 0 then
    Msg := Msg + ' (empty)'
  else
    Msg := Msg + ' "' + LandrixXmlEscapeForMessage(Shown, 40) + '"';
  raise ELandrixXmlError.CreateAt(xecConversion, Msg, 0, 0, Offset);
end;

function Utf8Ptr(const S: TLandrixXmlUtf8): PAnsiChar;
begin
  Result := PAnsiChar(S);
end;

{ Decimal digits of the magnitude of V (also for Low(Int64)). }
function MagnitudeDigits(V: Int64): AnsiString;
var
  Buf: array[0..23] of AnsiChar;
  I: Integer;
  M: Int64;
begin
  if V > 0 then
    M := -V
  else
    M := V;
  I := 23;
  repeat
    Buf[I] := AnsiChar(Ord('0') - Integer(M mod 10));
    Dec(I);
    M := M div 10;
  until M = 0;
  SetString(Result, PAnsiChar(@Buf[I + 1]), 23 - I);
end;

{ Formats the number Digits * 10^-Scale (Digits: decimal digits of the
  magnitude) with exactly Decimals decimals, rounded half away from zero. }
function FormatScaled(Neg: Boolean; Digits: AnsiString; Scale, Decimals: Integer): AnsiString;
var
  Cut, I: Integer;
  RoundUp, AllZero: Boolean;
begin
  while Length(Digits) <= Scale do
    Digits := '0' + Digits;
  if Decimals < Scale then
  begin
    Cut := Length(Digits) - (Scale - Decimals);
    RoundUp := Digits[Cut + 1] >= '5';
    SetLength(Digits, Cut);
    if RoundUp then
    begin
      I := Cut;
      while (I >= 1) and (Digits[I] = '9') do
      begin
        Digits[I] := '0';
        Dec(I);
      end;
      if I >= 1 then
        Digits[I] := AnsiChar(Ord(Digits[I]) + 1)
      else
        Digits := '1' + Digits;
    end;
  end
  else
    while Scale < Decimals do
    begin
      Digits := Digits + '0';
      Inc(Scale);
    end;
  while Length(Digits) <= Decimals do
    Digits := '0' + Digits;
  { drop leading zeros of the integer part, keep one }
  I := 1;
  while (I < Length(Digits) - Decimals) and (Digits[I] = '0') do
    Inc(I);
  if I > 1 then
    Delete(Digits, 1, I - 1);
  AllZero := True;
  for I := 1 to Length(Digits) do
    if Digits[I] <> '0' then
      AllZero := False;
  if Decimals > 0 then
    Insert('.', Digits, Length(Digits) - Decimals + 1);
  if Neg and not AllZero then
    Result := '-' + Digits
  else
    Result := Digits;
end;

function TrimDecimals(const S: AnsiString; MinDecimals: Integer): AnsiString;
var
  Dot, Last: Integer;
begin
  Result := S;
  Dot := Length(Result);
  while (Dot > 0) and (Result[Dot] <> '.') do
    Dec(Dot);
  if Dot = 0 then
    Exit;
  Last := Length(Result);
  while (Last - Dot > MinDecimals) and (Result[Last] = '0') do
    Dec(Last);
  if Last = Dot then
    Dec(Last);
  SetLength(Result, Last);
end;

procedure CheckDecimals(Decimals: Integer);
begin
  if (Decimals < 0) or (Decimals > 18) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument,
      'Decimals must be between 0 and 18');
end;

procedure CheckTrimRange(MinDecimals, MaxDecimals: Integer);
begin
  CheckDecimals(MaxDecimals);
  if (MinDecimals < 0) or (MinDecimals > MaxDecimals) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument,
      'MinDecimals must be between 0 and MaxDecimals');
end;

{ --- decimal scanner ------------------------------------------------------- }

{ Scans the xs:decimal form. Returns -1 or the offset of the first bad
  byte. IntS/IntE and FracS/FracE are the digit ranges. }
function ScanDecimal(P: PAnsiChar; Len: Integer; out Neg: Boolean;
  out IntS, IntE, FracS, FracE: Integer): Integer;
var
  S, E, I: Integer;
begin
  Neg := False;
  TrimRange(P, Len, S, E);
  IntS := S;
  IntE := S;
  FracS := S;
  FracE := S;
  Result := S;
  if S = E then
    Exit;
  I := S;
  if (P[I] = '+') or (P[I] = '-') then
  begin
    Neg := P[I] = '-';
    Inc(I);
  end;
  IntS := I;
  while (I < E) and IsDigit(P[I]) do
    Inc(I);
  IntE := I;
  FracS := I;
  FracE := I;
  if (I < E) and (P[I] = '.') then
  begin
    Inc(I);
    FracS := I;
    while (I < E) and IsDigit(P[I]) do
      Inc(I);
    FracE := I;
  end;
  if I < E then
  begin
    Result := I;
    Exit;
  end;
  if (IntE = IntS) and (FracE = FracS) then
  begin
    { no digit at all }
    if I > S then
      Result := I - 1
    else
      Result := S;
    Exit;
  end;
  Result := -1;
end;

{ --- Currency ------------------------------------------------------------ }

function CurrencyCore(P: PAnsiChar; Len: Integer; AllowRounding: Boolean;
  out Value: Currency; out Reason: Integer): Integer;
var
  Neg: Boolean;
  IntS, IntE, FracS, FracE, I, D: Integer;
  Acc, Raw: Int64;

  function Push(Digit: Integer): Boolean;
  begin
    { Acc holds the negated magnitude so that Low(Int64) fits }
    Result := (Acc > MinDiv10) or ((Acc = MinDiv10) and (Digit <= 8));
    if Result then
      Acc := Times10(Acc) - Digit;
  end;

begin
  PInt64(@Value)^ := 0;
  Reason := erSyntax;
  Result := ScanDecimal(P, Len, Neg, IntS, IntE, FracS, FracE);
  if Result >= 0 then
    Exit;
  Acc := 0;
  Reason := erRange;
  for I := IntS to IntE - 1 do
    if not Push(Ord(P[I]) - Ord('0')) then
    begin
      Result := IntS;
      Exit;
    end;
  for I := 0 to 3 do
  begin
    if FracS + I < FracE then
      D := Ord(P[FracS + I]) - Ord('0')
    else
      D := 0;
    if not Push(D) then
    begin
      Result := IntS;
      Exit;
    end;
  end;
  { digits beyond the fourth decimal }
  for I := FracS + 4 to FracE - 1 do
    if P[I] <> '0' then
    begin
      if not AllowRounding then
      begin
        Reason := erPrecision;
        Result := I;
        Exit;
      end;
      if P[FracS + 4] >= '5' then
      begin
        if Acc = Low(Int64) then
        begin
          Result := IntS;
          Exit;
        end;
        Acc := Acc - 1;
      end;
      Break;
    end;
  if Neg then
    Raw := Acc
  else
  begin
    if Acc = Low(Int64) then
    begin
      Result := IntS;
      Exit;
    end;
    Raw := -Acc;
  end;
  PInt64(@Value)^ := Raw;
  Result := -1;
end;

function LandrixXmlTryParseCurrencyBuf(P: PAnsiChar; Len: Integer; out Value: Currency;
  AllowRounding: Boolean): Boolean;
var
  Reason: Integer;
begin
  Result := CurrencyCore(P, Len, AllowRounding, Value, Reason) < 0;
end;

function LandrixXmlTryParseCurrency(const S: TLandrixXmlUtf8; out Value: Currency;
  AllowRounding: Boolean): Boolean;
begin
  Result := LandrixXmlTryParseCurrencyBuf(Utf8Ptr(S), Length(S), Value, AllowRounding);
end;

function LandrixXmlParseCurrencyBuf(P: PAnsiChar; Len: Integer;
  AllowRounding: Boolean): Currency;
var
  Bad, Reason: Integer;
begin
  Bad := CurrencyCore(P, Len, AllowRounding, Result, Reason);
  if Bad >= 0 then
    RaiseConversion('xs:decimal (Currency)', P, Len, Bad, Reason);
end;

function LandrixXmlParseCurrency(const S: TLandrixXmlUtf8; AllowRounding: Boolean): Currency;
begin
  Result := LandrixXmlParseCurrencyBuf(Utf8Ptr(S), Length(S), AllowRounding);
end;

function FormatCurrencyRaw(Value: Currency; Decimals: Integer): AnsiString;
var
  Raw: Int64;
begin
  Raw := PInt64(@Value)^;
  Result := FormatScaled(Raw < 0, MagnitudeDigits(Raw), 4, Decimals);
end;

function LandrixXmlFormatCurrency(Value: Currency; Decimals: Integer): TLandrixXmlUtf8;
begin
  CheckDecimals(Decimals);
  Result := ToUtf8(FormatCurrencyRaw(Value, Decimals));
end;

function LandrixXmlFormatCurrencyTrim(Value: Currency;
  MinDecimals, MaxDecimals: Integer): TLandrixXmlUtf8;
begin
  CheckTrimRange(MinDecimals, MaxDecimals);
  Result := ToUtf8(TrimDecimals(FormatCurrencyRaw(Value, MaxDecimals), MinDecimals));
end;

{ --- Double ---------------------------------------------------------------- }

function Pow10(N: Integer): Double;
var
  I: Integer;
begin
  { exact for N <= 22 }
  Result := 1;
  for I := 1 to N do
    Result := Result * 10;
end;

{ M * 10^Exp10 with a single IEEE rounding. On x87 (32-bit x86) the FPU
  computes with 64-bit mantissas and the store rounds again (double
  rounding), so the precision control is set to 53 bits for the operation. }
function ScaleExact(M: Int64; Exp10: Integer): Double;
{$IFDEF CPU386}
var
  Saved: Word;
{$ENDIF}
begin
{$IFDEF CPU386}
  Saved := Get8087CW;
  Set8087CW(Word((Saved and not $0300) or $0200));
  try
{$ENDIF}
    Result := M;
    if Exp10 > 0 then
      Result := Result * Pow10(Exp10)
    else if Exp10 < 0 then
      Result := Result / Pow10(-Exp10);
{$IFDEF CPU386}
  finally
    Set8087CW(Saved);
  end;
{$ENDIF}
end;

{ True if Digits * 10^Exp10 (Digits without leading zeros) is at or near
  the largest double. Checked before Val, because Val may overflow there
  (FPC rounds inexactly; on x86 the overflow raises EOverflow, on x87 even
  delayed to a later instruction). Values within about 15 ulps of the
  largest double are conservatively reported as out of range. }
function AboveMaxDouble(const Digits: AnsiString; Exp10: Integer): Boolean;
const
  { the first 15 digits of the largest double, 1.79769313486231570e308 }
  Limit: AnsiString = '179769313486231';
var
  IntDigits, I: Integer;
  C: AnsiChar;
begin
  IntDigits := Length(Digits) + Exp10;
  if IntDigits <> 309 then
  begin
    Result := IntDigits > 309;
    Exit;
  end;
  for I := 1 to Length(Limit) do
  begin
    if I <= Length(Digits) then
      C := Digits[I]
    else
      C := '0';
    if C <> Limit[I] then
    begin
      Result := C > Limit[I];
      Exit;
    end;
  end;
  { prefix equal to the limit: conservatively out of range }
  Result := True;
end;

function DoubleCore(P: PAnsiChar; Len: Integer; out Value: Double;
  out Reason: Integer): Integer;
var
  Neg: Boolean;
  IntS, IntE, FracS, FracE, I, Exp10, N, Digit: Integer;
  Sticky: Boolean;
  Digits: AnsiString;
  M: Int64;
  S: string;
  Code: Integer;
  D: Double;
begin
  Value := 0;
  Reason := erSyntax;
  Result := ScanDecimal(P, Len, Neg, IntS, IntE, FracS, FracE);
  if Result >= 0 then
    Exit;
  { significant digits and power of ten }
  SetString(Digits, P + IntS, IntE - IntS);
  N := Length(Digits);
  SetLength(Digits, N + (FracE - FracS));
  if FracE > FracS then
    Move(P[FracS], Digits[N + 1], FracE - FracS);
  Exp10 := -(FracE - FracS);
  I := 1;
  while (I <= Length(Digits)) and (Digits[I] = '0') do
    Inc(I);
  if I > 1 then
    Delete(Digits, 1, I - 1);
  while (Digits <> '') and (Digits[Length(Digits)] = '0') do
  begin
    SetLength(Digits, Length(Digits) - 1);
    Inc(Exp10);
  end;
  if Digits = '' then
  begin
    Result := -1;
    Exit;
  end;
  if AboveMaxDouble(Digits, Exp10) then
  begin
    Reason := erRange;
    Result := IntS;
    Exit;
  end;
  if (Length(Digits) <= 16) and (Exp10 >= -22) and (Exp10 <= 22 + 16) then
  begin
    M := 0;
    for I := 1 to Length(Digits) do
    begin
      Digit := Ord(Digits[I]) - Ord('0');
      M := Times10(M) + Digit;
    end;
    { move surplus powers of ten into the mantissa while it stays exact }
    while (Exp10 > 22) and (M <= 900719925474099) do
    begin
      M := Times10(M);
      Dec(Exp10);
    end;
    if (M <= 9007199254740992) and (Exp10 <= 22) then
    begin
      { both operands exact: one correctly rounded operation }
      D := ScaleExact(M, Exp10);
      if Neg then
        D := -D;
      Value := D;
      Result := -1;
      Exit;
    end;
  end;
  { long mantissas: the RTL (locale-independent, input validated above).
    At most 20 significant digits: FPC's Val rejects strings longer than
    255 characters and Delphi 13 Win64 returns 0 for very long ones; the
    20th digit is made non-zero when a dropped digit was, so the rounding
    direction is kept. }
  if Length(Digits) > 20 then
  begin
    Sticky := False;
    for I := 21 to Length(Digits) do
      if Digits[I] <> '0' then
        Sticky := True;
    Inc(Exp10, Length(Digits) - 20);
    SetLength(Digits, 20);
    if Sticky and (Digits[20] = '0') then
      Digits[20] := '1';
  end;
  S := '';
  SetLength(S, Length(Digits));
  for I := 1 to Length(Digits) do
    S[I] := Char(Ord(Digits[I]));
  S := S + 'E' + IntToStr(Exp10);
  Val(S, D, Code);
  if (Code <> 0) or ((PInt64(@D)^ shr 52) and $7FF = $7FF) then
  begin
    Reason := erRange;
    Result := IntS;
    Exit;
  end;
  if Neg then
    D := -D;
  Value := D;
  Result := -1;
end;

function LandrixXmlTryParseDoubleBuf(P: PAnsiChar; Len: Integer; out Value: Double): Boolean;
var
  Reason: Integer;
begin
  Result := DoubleCore(P, Len, Value, Reason) < 0;
  if not Result then
    Value := 0;
end;

function LandrixXmlTryParseDouble(const S: TLandrixXmlUtf8; out Value: Double): Boolean;
begin
  Result := LandrixXmlTryParseDoubleBuf(Utf8Ptr(S), Length(S), Value);
end;

function LandrixXmlParseDoubleBuf(P: PAnsiChar; Len: Integer): Double;
var
  Bad, Reason: Integer;
begin
  Bad := DoubleCore(P, Len, Result, Reason);
  if Bad >= 0 then
    RaiseConversion('xs:decimal (Double)', P, Len, Bad, Reason);
end;

function LandrixXmlParseDouble(const S: TLandrixXmlUtf8): Double;
begin
  Result := LandrixXmlParseDoubleBuf(Utf8Ptr(S), Length(S));
end;

function FormatDoubleRaw(Value: Double; Decimals: Integer): AnsiString;
var
  A, Power: Double;
  E, K, I, Scale, Extra: Integer;
  SS: ShortString;
  Digits: AnsiString;
  Seen: Boolean;
begin
  if (PInt64(@Value)^ shr 52) and $7FF = $7FF then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument,
      'NaN and infinite values have no xs:decimal form');
  A := Abs(Value);
  if A = 0 then
  begin
    Result := FormatScaled(False, '0', 0, Decimals);
    Exit;
  end;
  { decimal exponent E with 10^E <= A < 10^(E+1) (approximately) }
  E := 0;
  Power := 1;
  if A >= 1 then
    { stops at 1e23 (the formatting limit), so Power never overflows }
    while (A >= Power * 10) and (E < 23) do
    begin
      Power := Power * 10;
      Inc(E);
    end
  else
    while (A < Power) and (E > -400) do
    begin
      Power := Power / 10;
      Dec(E);
    end;
  { Str prints fixed notation up to 1e22 on every compiler }
  if E > 22 then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument,
      'Value too large for xs:decimal formatting (limit 1e23)');
  { 15 significant digits }
  K := 14 - E;
  if K > 18 then
    K := 18;
  if K < 0 then
    K := 0;
  Str(A:0:K, SS);
  Digits := '';
  Scale := 0;
  Seen := False;
  for I := 1 to Length(SS) do
    if SS[I] = '.' then
      Seen := True
    else if (SS[I] >= '0') and (SS[I] <= '9') then
    begin
      Digits := Digits + SS[I];
      if Seen then
        Inc(Scale);
    end
    else
      raise ELandrixXmlError.CreateCode(xecInvalidArgument,
        'Value too large for xs:decimal formatting');
  { above 1e15 the RTLs print different digits beyond the 15th: round to
    15 significant digits and fill with zeros }
  if Length(Digits) - Scale > 15 then
  begin
    Extra := Length(Digits) - Scale - 15;
    Digits := FormatScaled(False, Copy(Digits, 1, Length(Digits) - Scale), Extra, 0);
    for I := 1 to Extra do
      Digits := Digits + '0';
    Scale := 0;
  end;
  Result := FormatScaled(Value < 0, Digits, Scale, Decimals);
end;

function LandrixXmlFormatDouble(Value: Double; Decimals: Integer): TLandrixXmlUtf8;
begin
  CheckDecimals(Decimals);
  Result := ToUtf8(FormatDoubleRaw(Value, Decimals));
end;

function LandrixXmlFormatDoubleTrim(Value: Double;
  MinDecimals, MaxDecimals: Integer): TLandrixXmlUtf8;
begin
  CheckTrimRange(MinDecimals, MaxDecimals);
  Result := ToUtf8(TrimDecimals(FormatDoubleRaw(Value, MaxDecimals), MinDecimals));
end;

{ --- integers ---------------------------------------------------------------- }

function Int64Core(P: PAnsiChar; Len: Integer; out Value: Int64; out Reason: Integer): Integer;
var
  S, E, I, D: Integer;
  Neg: Boolean;
  Acc: Int64;
begin
  Value := 0;
  Reason := erSyntax;
  TrimRange(P, Len, S, E);
  Result := S;
  if S = E then
    Exit;
  I := S;
  Neg := False;
  if (P[I] = '+') or (P[I] = '-') then
  begin
    Neg := P[I] = '-';
    Inc(I);
  end;
  if I = E then
  begin
    Result := I - 1;
    Exit;
  end;
  Acc := 0;
  while I < E do
  begin
    if not IsDigit(P[I]) then
    begin
      Result := I;
      Exit;
    end;
    D := Ord(P[I]) - Ord('0');
    if not ((Acc > MinDiv10) or ((Acc = MinDiv10) and (D <= 8))) then
    begin
      Reason := erRange;
      Result := S;
      Exit;
    end;
    Acc := Times10(Acc) - D;
    Inc(I);
  end;
  if Neg then
    Value := Acc
  else
  begin
    if Acc = Low(Int64) then
    begin
      Reason := erRange;
      Result := S;
      Exit;
    end;
    Value := -Acc;
  end;
  Result := -1;
end;

function LandrixXmlTryParseInt64Buf(P: PAnsiChar; Len: Integer; out Value: Int64): Boolean;
var
  Reason: Integer;
begin
  Result := Int64Core(P, Len, Value, Reason) < 0;
  if not Result then
    Value := 0;
end;

function LandrixXmlTryParseInt64(const S: TLandrixXmlUtf8; out Value: Int64): Boolean;
begin
  Result := LandrixXmlTryParseInt64Buf(Utf8Ptr(S), Length(S), Value);
end;

function LandrixXmlParseInt64Buf(P: PAnsiChar; Len: Integer): Int64;
var
  Bad, Reason: Integer;
begin
  Bad := Int64Core(P, Len, Result, Reason);
  if Bad >= 0 then
    RaiseConversion('xs:long', P, Len, Bad, Reason);
end;

function LandrixXmlParseInt64(const S: TLandrixXmlUtf8): Int64;
begin
  Result := LandrixXmlParseInt64Buf(Utf8Ptr(S), Length(S));
end;

function IntegerCore(P: PAnsiChar; Len: Integer; out Value: Integer; out Reason: Integer): Integer;
var
  V: Int64;
  E: Integer;
begin
  Value := 0;
  Result := Int64Core(P, Len, V, Reason);
  if Result >= 0 then
    Exit;
  if (V < Low(Integer)) or (V > High(Integer)) then
  begin
    Reason := erRange;
    TrimRange(P, Len, Result, E);
    Exit;
  end;
  Value := Integer(V);
end;

function LandrixXmlTryParseIntegerBuf(P: PAnsiChar; Len: Integer; out Value: Integer): Boolean;
var
  Reason: Integer;
begin
  Result := IntegerCore(P, Len, Value, Reason) < 0;
  if not Result then
    Value := 0;
end;

function LandrixXmlTryParseInteger(const S: TLandrixXmlUtf8; out Value: Integer): Boolean;
begin
  Result := LandrixXmlTryParseIntegerBuf(Utf8Ptr(S), Length(S), Value);
end;

function LandrixXmlParseIntegerBuf(P: PAnsiChar; Len: Integer): Integer;
var
  Bad, Reason: Integer;
begin
  Bad := IntegerCore(P, Len, Result, Reason);
  if Bad >= 0 then
    RaiseConversion('xs:int', P, Len, Bad, Reason);
end;

function LandrixXmlParseInteger(const S: TLandrixXmlUtf8): Integer;
begin
  Result := LandrixXmlParseIntegerBuf(Utf8Ptr(S), Length(S));
end;

function LandrixXmlFormatInt64(Value: Int64): TLandrixXmlUtf8;
begin
  if Value < 0 then
    Result := ToUtf8('-' + MagnitudeDigits(Value))
  else
    Result := ToUtf8(MagnitudeDigits(Value));
end;

{ --- Boolean ---------------------------------------------------------------- }

function SameRange(P: PAnsiChar; S, E: Integer; const A: AnsiString): Boolean;
var
  I: Integer;
begin
  Result := E - S = Length(A);
  I := 0;
  while Result and (I < Length(A)) do
  begin
    Result := P[S + I] = A[I + 1];
    Inc(I);
  end;
end;

function BooleanCore(P: PAnsiChar; Len: Integer; out Value: Boolean): Integer;
var
  S, E: Integer;
begin
  Value := False;
  TrimRange(P, Len, S, E);
  Result := -1;
  if SameRange(P, S, E, 'true') or SameRange(P, S, E, '1') then
    Value := True
  else if not (SameRange(P, S, E, 'false') or SameRange(P, S, E, '0')) then
    Result := S;
end;

function LandrixXmlTryParseBooleanBuf(P: PAnsiChar; Len: Integer; out Value: Boolean): Boolean;
begin
  Result := BooleanCore(P, Len, Value) < 0;
end;

function LandrixXmlTryParseBoolean(const S: TLandrixXmlUtf8; out Value: Boolean): Boolean;
begin
  Result := LandrixXmlTryParseBooleanBuf(Utf8Ptr(S), Length(S), Value);
end;

function LandrixXmlParseBooleanBuf(P: PAnsiChar; Len: Integer): Boolean;
var
  Bad: Integer;
begin
  Bad := BooleanCore(P, Len, Result);
  if Bad >= 0 then
    RaiseConversion('xs:boolean', P, Len, Bad, erSyntax);
end;

function LandrixXmlParseBoolean(const S: TLandrixXmlUtf8): Boolean;
begin
  Result := LandrixXmlParseBooleanBuf(Utf8Ptr(S), Length(S));
end;

function LandrixXmlFormatBoolean(Value: Boolean): TLandrixXmlUtf8;
begin
  if Value then
    Result := 'true'
  else
    Result := 'false';
end;

{ --- date and time core ------------------------------------------------------ }

function IsLeapYear(Year: Integer): Boolean;
begin
  Result := (Year mod 4 = 0) and ((Year mod 100 <> 0) or (Year mod 400 = 0));
end;

function DaysInMonth(Year, Month: Integer): Integer;
begin
  case Month of
    2:
      if IsLeapYear(Year) then
        Result := 29
      else
        Result := 28;
    4, 6, 9, 11:
      Result := 30;
  else
    Result := 31;
  end;
end;

procedure ClearParts(out Value: TLandrixXmlDateTime);
begin
  Value.Year := 0;
  Value.Month := 0;
  Value.Day := 0;
  Value.Hour := 0;
  Value.Minute := 0;
  Value.Second := 0;
  Value.Millisecond := 0;
  Value.HasTimeZone := False;
  Value.TimeZoneMinutes := 0;
end;

{ Reads exactly Count digits at P[I]; False if there are fewer. }
function ReadNum(P: PAnsiChar; var I: Integer; E, Count: Integer; out V: Integer): Boolean;
var
  K: Integer;
begin
  V := 0;
  Result := False;
  for K := 1 to Count do
  begin
    if (I >= E) or not IsDigit(P[I]) then
      Exit;
    V := V * 10 + (Ord(P[I]) - Ord('0'));
    Inc(I);
  end;
  Result := True;
end;

function Expect(P: PAnsiChar; var I: Integer; E: Integer; C: AnsiChar): Boolean;
begin
  Result := (I < E) and (P[I] = C);
  if Result then
    Inc(I);
end;

{ YYYY-MM-DD; returns -1 or the bad offset. }
function ScanDate(P: PAnsiChar; var I: Integer; E: Integer;
  var Value: TLandrixXmlDateTime; out Reason: Integer): Integer;
var
  Start: Integer;
begin
  Reason := erSyntax;
  Start := I;
  Result := I;
  if not ReadNum(P, I, E, 4, Value.Year) then
    Exit;
  if (I < E) and IsDigit(P[I]) then
  begin
    { years beyond 9999 are valid XML Schema but not supported }
    Reason := erRange;
    Result := Start;
    Exit;
  end;
  Result := I;
  if not Expect(P, I, E, '-') then
    Exit;
  Result := I;
  if not ReadNum(P, I, E, 2, Value.Month) then
    Exit;
  Result := I;
  if not Expect(P, I, E, '-') then
    Exit;
  Result := I;
  if not ReadNum(P, I, E, 2, Value.Day) then
    Exit;
  Reason := erDate;
  Result := Start;
  if (Value.Year < 1) or (Value.Month < 1) or (Value.Month > 12) or (Value.Day < 1) or
    (Value.Day > DaysInMonth(Value.Year, Value.Month)) then
    Exit;
  Reason := erSyntax;
  Result := -1;
end;

{ hh:mm:ss[.f+]; End24 is True for 24:00:00. }
function ScanTime(P: PAnsiChar; var I: Integer; E: Integer;
  var Value: TLandrixXmlDateTime; out End24: Boolean; out Reason: Integer): Integer;
var
  Start, Digits: Integer;
  FracZero: Boolean;
begin
  Reason := erSyntax;
  End24 := False;
  Start := I;
  Result := I;
  if not ReadNum(P, I, E, 2, Value.Hour) then
    Exit;
  Result := I;
  if not Expect(P, I, E, ':') then
    Exit;
  Result := I;
  if not ReadNum(P, I, E, 2, Value.Minute) then
    Exit;
  Result := I;
  if not Expect(P, I, E, ':') then
    Exit;
  Result := I;
  if not ReadNum(P, I, E, 2, Value.Second) then
    Exit;
  FracZero := True;
  Value.Millisecond := 0;
  if (I < E) and (P[I] = '.') then
  begin
    Inc(I);
    Result := I;
    if (I >= E) or not IsDigit(P[I]) then
      Exit;
    Digits := 0;
    while (I < E) and IsDigit(P[I]) do
    begin
      if P[I] <> '0' then
        FracZero := False;
      { milliseconds: the first three digits, the rest is truncated }
      if Digits < 3 then
        Value.Millisecond := Value.Millisecond * 10 + (Ord(P[I]) - Ord('0'));
      Inc(Digits);
      Inc(I);
    end;
    while Digits < 3 do
    begin
      Value.Millisecond := Value.Millisecond * 10;
      Inc(Digits);
    end;
  end;
  Reason := erDate;
  Result := Start;
  if (Value.Hour = 24) and (Value.Minute = 0) and (Value.Second = 0) and FracZero then
  begin
    End24 := True;
    Value.Hour := 0;
  end
  else if (Value.Hour > 23) or (Value.Minute > 59) or (Value.Second > 59) then
    Exit;
  Reason := erSyntax;
  Result := -1;
end;

{ Optional Z or +hh:mm / -hh:mm. }
function ScanZone(P: PAnsiChar; var I: Integer; E: Integer;
  var Value: TLandrixXmlDateTime; out Reason: Integer): Integer;
var
  Start, H, M: Integer;
  Neg: Boolean;
begin
  Reason := erSyntax;
  Result := -1;
  if I >= E then
    Exit;
  Start := I;
  if P[I] = 'Z' then
  begin
    Inc(I);
    Value.HasTimeZone := True;
    Value.TimeZoneMinutes := 0;
    Exit;
  end;
  if (P[I] <> '+') and (P[I] <> '-') then
  begin
    Result := I;
    Exit;
  end;
  Neg := P[I] = '-';
  Inc(I);
  Result := I;
  if not ReadNum(P, I, E, 2, H) then
    Exit;
  Result := I;
  if not Expect(P, I, E, ':') then
    Exit;
  Result := I;
  if not ReadNum(P, I, E, 2, M) then
    Exit;
  if (M > 59) or (H > 14) or ((H = 14) and (M > 0)) then
  begin
    Reason := erDate;
    Result := Start;
    Exit;
  end;
  Value.HasTimeZone := True;
  Value.TimeZoneMinutes := H * 60 + M;
  if Neg then
    Value.TimeZoneMinutes := -Value.TimeZoneMinutes;
  Result := -1;
end;

{ Kind: 0 = date, 1 = dateTime, 2 = time }
function DateTimeCore(P: PAnsiChar; Len: Integer; Kind: Integer;
  out Value: TLandrixXmlDateTime; out Reason: Integer): Integer;
var
  S, E, I: Integer;
  End24: Boolean;
begin
  ClearParts(Value);
  Reason := erSyntax;
  TrimRange(P, Len, S, E);
  Result := S;
  if S = E then
    Exit;
  I := S;
  End24 := False;
  if Kind <> 2 then
  begin
    Result := ScanDate(P, I, E, Value, Reason);
    if Result >= 0 then
      Exit;
  end;
  if Kind = 1 then
  begin
    Result := I;
    if not Expect(P, I, E, 'T') then
      Exit;
  end;
  if Kind <> 0 then
  begin
    Result := ScanTime(P, I, E, Value, End24, Reason);
    if Result >= 0 then
      Exit;
  end;
  Result := ScanZone(P, I, E, Value, Reason);
  if Result >= 0 then
    Exit;
  if I < E then
  begin
    Reason := erSyntax;
    Result := I;
    Exit;
  end;
  if End24 and (Kind = 1) then
  begin
    { 24:00:00 is 00:00:00 of the next day }
    Inc(Value.Day);
    if Value.Day > DaysInMonth(Value.Year, Value.Month) then
    begin
      Value.Day := 1;
      Inc(Value.Month);
      if Value.Month > 12 then
      begin
        Value.Month := 1;
        Inc(Value.Year);
        if Value.Year > 9999 then
        begin
          Reason := erRange;
          Result := S;
          Exit;
        end;
      end;
    end;
  end;
  Result := -1;
end;

function DateTypeName(Kind: Integer): string;
begin
  case Kind of
    0: Result := 'xs:date';
    1: Result := 'xs:dateTime';
  else
    Result := 'xs:time';
  end;
end;

function TryParts(P: PAnsiChar; Len, Kind: Integer; out Value: TLandrixXmlDateTime): Boolean;
var
  Reason: Integer;
begin
  Result := DateTimeCore(P, Len, Kind, Value, Reason) < 0;
  if not Result then
    ClearParts(Value);
end;

function ParseParts(P: PAnsiChar; Len, Kind: Integer): TLandrixXmlDateTime;
var
  Bad, Reason: Integer;
begin
  Bad := DateTimeCore(P, Len, Kind, Result, Reason);
  if Bad >= 0 then
    RaiseConversion(DateTypeName(Kind), P, Len, Bad, Reason);
end;

function LandrixXmlTryParseDatePartsBuf(P: PAnsiChar; Len: Integer;
  out Value: TLandrixXmlDateTime): Boolean;
begin
  Result := TryParts(P, Len, 0, Value);
end;

function LandrixXmlTryParseDateParts(const S: TLandrixXmlUtf8;
  out Value: TLandrixXmlDateTime): Boolean;
begin
  Result := TryParts(Utf8Ptr(S), Length(S), 0, Value);
end;

function LandrixXmlParseDatePartsBuf(P: PAnsiChar; Len: Integer): TLandrixXmlDateTime;
begin
  Result := ParseParts(P, Len, 0);
end;

function LandrixXmlParseDateParts(const S: TLandrixXmlUtf8): TLandrixXmlDateTime;
begin
  Result := ParseParts(Utf8Ptr(S), Length(S), 0);
end;

function LandrixXmlTryParseDateTimePartsBuf(P: PAnsiChar; Len: Integer;
  out Value: TLandrixXmlDateTime): Boolean;
begin
  Result := TryParts(P, Len, 1, Value);
end;

function LandrixXmlTryParseDateTimeParts(const S: TLandrixXmlUtf8;
  out Value: TLandrixXmlDateTime): Boolean;
begin
  Result := TryParts(Utf8Ptr(S), Length(S), 1, Value);
end;

function LandrixXmlParseDateTimePartsBuf(P: PAnsiChar; Len: Integer): TLandrixXmlDateTime;
begin
  Result := ParseParts(P, Len, 1);
end;

function LandrixXmlParseDateTimeParts(const S: TLandrixXmlUtf8): TLandrixXmlDateTime;
begin
  Result := ParseParts(Utf8Ptr(S), Length(S), 1);
end;

function LandrixXmlTryParseTimePartsBuf(P: PAnsiChar; Len: Integer;
  out Value: TLandrixXmlDateTime): Boolean;
begin
  Result := TryParts(P, Len, 2, Value);
end;

function LandrixXmlTryParseTimeParts(const S: TLandrixXmlUtf8;
  out Value: TLandrixXmlDateTime): Boolean;
begin
  Result := TryParts(Utf8Ptr(S), Length(S), 2, Value);
end;

function LandrixXmlParseTimePartsBuf(P: PAnsiChar; Len: Integer): TLandrixXmlDateTime;
begin
  Result := ParseParts(P, Len, 2);
end;

function LandrixXmlParseTimeParts(const S: TLandrixXmlUtf8): TLandrixXmlDateTime;
begin
  Result := ParseParts(Utf8Ptr(S), Length(S), 2);
end;

{ --- parts <-> TDateTime --------------------------------------------------- }

procedure CheckParts(const Value: TLandrixXmlDateTime; NeedDate, NeedTime: Boolean);
var
  Ok: Boolean;
begin
  Ok := True;
  if NeedDate then
    Ok := (Value.Year >= 1) and (Value.Year <= 9999) and (Value.Month >= 1) and
      (Value.Month <= 12) and (Value.Day >= 1) and
      (Value.Day <= DaysInMonth(Value.Year, Value.Month));
  if NeedTime then
    Ok := Ok and (Value.Hour >= 0) and (Value.Hour <= 23) and (Value.Minute >= 0) and
      (Value.Minute <= 59) and (Value.Second >= 0) and (Value.Second <= 59) and
      (Value.Millisecond >= 0) and (Value.Millisecond <= 999);
  if Value.HasTimeZone then
    Ok := Ok and (Value.TimeZoneMinutes >= -840) and (Value.TimeZoneMinutes <= 840);
  if not Ok then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'Invalid date or time parts');
end;

function LandrixXmlPartsToDateTime(const Value: TLandrixXmlDateTime): TDateTime;
var
  D, T: TDateTime;
begin
  CheckParts(Value, Value.Year <> 0, True);
  T := EncodeTime(Word(Value.Hour), Word(Value.Minute), Word(Value.Second),
    Word(Value.Millisecond));
  if Value.Year = 0 then
  begin
    Result := T;
    Exit;
  end;
  D := EncodeDate(Word(Value.Year), Word(Value.Month), Word(Value.Day));
  { before 1899-12-30 the time is counted away from zero }
  if D < 0 then
    Result := D - T
  else
    Result := D + T;
end;

function LandrixXmlDateTimeToParts(Value: TDateTime): TLandrixXmlDateTime;
var
  Y, M, D, H, N, S, MS: Word;
begin
  { 0001-01-01 .. 9999-12-31 }
  if (Value <= -693594) or (Value >= 2958466) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'Date outside 0001-9999');
  ClearParts(Result);
  DecodeDate(Value, Y, M, D);
  DecodeTime(Value, H, N, S, MS);
  Result.Year := Y;
  Result.Month := M;
  Result.Day := D;
  Result.Hour := H;
  Result.Minute := N;
  Result.Second := S;
  Result.Millisecond := MS;
end;

{ --- TDateTime convenience ------------------------------------------------- }

function TryKind(P: PAnsiChar; Len, Kind: Integer; out Value: TDateTime): Boolean;
var
  Parts: TLandrixXmlDateTime;
begin
  Value := 0;
  Result := TryParts(P, Len, Kind, Parts);
  if Result then
    Value := LandrixXmlPartsToDateTime(Parts);
end;

function ParseKind(P: PAnsiChar; Len, Kind: Integer): TDateTime;
begin
  Result := LandrixXmlPartsToDateTime(ParseParts(P, Len, Kind));
end;

function LandrixXmlTryParseDateBuf(P: PAnsiChar; Len: Integer; out Value: TDateTime): Boolean;
begin
  Result := TryKind(P, Len, 0, Value);
end;

function LandrixXmlTryParseDate(const S: TLandrixXmlUtf8; out Value: TDateTime): Boolean;
begin
  Result := TryKind(Utf8Ptr(S), Length(S), 0, Value);
end;

function LandrixXmlParseDateBuf(P: PAnsiChar; Len: Integer): TDateTime;
begin
  Result := ParseKind(P, Len, 0);
end;

function LandrixXmlParseDate(const S: TLandrixXmlUtf8): TDateTime;
begin
  Result := ParseKind(Utf8Ptr(S), Length(S), 0);
end;

function LandrixXmlTryParseDateTimeBuf(P: PAnsiChar; Len: Integer; out Value: TDateTime): Boolean;
begin
  Result := TryKind(P, Len, 1, Value);
end;

function LandrixXmlTryParseDateTime(const S: TLandrixXmlUtf8; out Value: TDateTime): Boolean;
begin
  Result := TryKind(Utf8Ptr(S), Length(S), 1, Value);
end;

function LandrixXmlParseDateTimeBuf(P: PAnsiChar; Len: Integer): TDateTime;
begin
  Result := ParseKind(P, Len, 1);
end;

function LandrixXmlParseDateTime(const S: TLandrixXmlUtf8): TDateTime;
begin
  Result := ParseKind(Utf8Ptr(S), Length(S), 1);
end;

function LandrixXmlTryParseTimeBuf(P: PAnsiChar; Len: Integer; out Value: TDateTime): Boolean;
begin
  Result := TryKind(P, Len, 2, Value);
end;

function LandrixXmlTryParseTime(const S: TLandrixXmlUtf8; out Value: TDateTime): Boolean;
begin
  Result := TryKind(Utf8Ptr(S), Length(S), 2, Value);
end;

function LandrixXmlParseTimeBuf(P: PAnsiChar; Len: Integer): TDateTime;
begin
  Result := ParseKind(P, Len, 2);
end;

function LandrixXmlParseTime(const S: TLandrixXmlUtf8): TDateTime;
begin
  Result := ParseKind(Utf8Ptr(S), Length(S), 2);
end;

{ --- formatting dates ------------------------------------------------------- }

function Pad(V, Width: Integer): AnsiString;
begin
  Result := MagnitudeDigits(V);
  while Length(Result) < Width do
    Result := '0' + Result;
end;

function DatePart(const Value: TLandrixXmlDateTime): AnsiString;
begin
  Result := Pad(Value.Year, 4) + '-' + Pad(Value.Month, 2) + '-' + Pad(Value.Day, 2);
end;

function TimePart(const Value: TLandrixXmlDateTime): AnsiString;
begin
  Result := Pad(Value.Hour, 2) + ':' + Pad(Value.Minute, 2) + ':' + Pad(Value.Second, 2);
  if Value.Millisecond <> 0 then
    Result := Result + '.' + Pad(Value.Millisecond, 3);
end;

function ZonePart(const Value: TLandrixXmlDateTime): AnsiString;
var
  M: Integer;
begin
  Result := '';
  if not Value.HasTimeZone then
    Exit;
  M := Value.TimeZoneMinutes;
  if M = 0 then
  begin
    Result := 'Z';
    Exit;
  end;
  if M < 0 then
  begin
    Result := '-';
    M := -M;
  end
  else
    Result := '+';
  Result := Result + Pad(M div 60, 2) + ':' + Pad(M mod 60, 2);
end;

function LandrixXmlFormatDateParts(const Value: TLandrixXmlDateTime): TLandrixXmlUtf8;
begin
  CheckParts(Value, True, False);
  Result := ToUtf8(DatePart(Value) + ZonePart(Value));
end;

function LandrixXmlFormatDateTimeParts(const Value: TLandrixXmlDateTime): TLandrixXmlUtf8;
begin
  CheckParts(Value, True, True);
  Result := ToUtf8(DatePart(Value) + 'T' + TimePart(Value) + ZonePart(Value));
end;

function LandrixXmlFormatTimeParts(const Value: TLandrixXmlDateTime): TLandrixXmlUtf8;
begin
  CheckParts(Value, False, True);
  Result := ToUtf8(TimePart(Value) + ZonePart(Value));
end;

function LandrixXmlFormatDate(Value: TDateTime): TLandrixXmlUtf8;
begin
  Result := LandrixXmlFormatDateParts(LandrixXmlDateTimeToParts(Value));
end;

function LandrixXmlFormatDateTime(Value: TDateTime): TLandrixXmlUtf8;
begin
  Result := LandrixXmlFormatDateTimeParts(LandrixXmlDateTimeToParts(Value));
end;

function LandrixXmlFormatDateTimeTz(Value: TDateTime; TimeZoneMinutes: Integer): TLandrixXmlUtf8;
var
  Parts: TLandrixXmlDateTime;
begin
  Parts := LandrixXmlDateTimeToParts(Value);
  Parts.HasTimeZone := True;
  Parts.TimeZoneMinutes := TimeZoneMinutes;
  Result := LandrixXmlFormatDateTimeParts(Parts);
end;

function LandrixXmlFormatTime(Value: TDateTime): TLandrixXmlUtf8;
var
  Parts: TLandrixXmlDateTime;
begin
  Parts := LandrixXmlDateTimeToParts(Value);
  Result := LandrixXmlFormatTimeParts(Parts);
end;

{ --- CII date formats ------------------------------------------------------- }

function CiiCore(P: PAnsiChar; Len, Format: Integer; out Value: TLandrixXmlDateTime;
  out Reason: Integer): Integer;
var
  S, E, I: Integer;
begin
  ClearParts(Value);
  Reason := erSyntax;
  if (Format <> 102) and (Format <> 610) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument,
      'Unsupported CII date format ' + IntToStr(Format));
  TrimRange(P, Len, S, E);
  I := S;
  if not ReadNum(P, I, E, 4, Value.Year) then
  begin
    Result := I;
    Exit;
  end;
  if not ReadNum(P, I, E, 2, Value.Month) then
  begin
    Result := I;
    Exit;
  end;
  if (Format = 102) and not ReadNum(P, I, E, 2, Value.Day) then
  begin
    Result := I;
    Exit;
  end;
  if I < E then
  begin
    Result := I;
    Exit;
  end;
  Reason := erDate;
  Result := S;
  if (Value.Year < 1) or (Value.Month < 1) or (Value.Month > 12) then
    Exit;
  if (Format = 102) and ((Value.Day < 1) or (Value.Day > DaysInMonth(Value.Year, Value.Month))) then
    Exit;
  Reason := erSyntax;
  Result := -1;
end;

function CiiTypeName(Format: Integer): string;
begin
  Result := 'CII date format ' + IntToStr(Format);
end;

function LandrixXmlTryParseCiiDatePartsBuf(P: PAnsiChar; Len: Integer; Format: Integer;
  out Value: TLandrixXmlDateTime): Boolean;
var
  Reason: Integer;
begin
  Result := CiiCore(P, Len, Format, Value, Reason) < 0;
  if not Result then
    ClearParts(Value);
end;

function LandrixXmlTryParseCiiDateParts(const S: TLandrixXmlUtf8; Format: Integer;
  out Value: TLandrixXmlDateTime): Boolean;
begin
  Result := LandrixXmlTryParseCiiDatePartsBuf(Utf8Ptr(S), Length(S), Format, Value);
end;

function LandrixXmlParseCiiDatePartsBuf(P: PAnsiChar; Len: Integer;
  Format: Integer): TLandrixXmlDateTime;
var
  Bad, Reason: Integer;
begin
  Bad := CiiCore(P, Len, Format, Result, Reason);
  if Bad >= 0 then
    RaiseConversion(CiiTypeName(Format), P, Len, Bad, Reason);
end;

function LandrixXmlParseCiiDateParts(const S: TLandrixXmlUtf8;
  Format: Integer): TLandrixXmlDateTime;
begin
  Result := LandrixXmlParseCiiDatePartsBuf(Utf8Ptr(S), Length(S), Format);
end;

function LandrixXmlTryParseCiiDateBuf(P: PAnsiChar; Len: Integer; out Value: TDateTime): Boolean;
var
  Parts: TLandrixXmlDateTime;
begin
  Value := 0;
  Result := LandrixXmlTryParseCiiDatePartsBuf(P, Len, 102, Parts);
  if Result then
    Value := LandrixXmlPartsToDateTime(Parts);
end;

function LandrixXmlTryParseCiiDate(const S: TLandrixXmlUtf8; out Value: TDateTime): Boolean;
begin
  Result := LandrixXmlTryParseCiiDateBuf(Utf8Ptr(S), Length(S), Value);
end;

function LandrixXmlParseCiiDateBuf(P: PAnsiChar; Len: Integer): TDateTime;
begin
  Result := LandrixXmlPartsToDateTime(LandrixXmlParseCiiDatePartsBuf(P, Len, 102));
end;

function LandrixXmlParseCiiDate(const S: TLandrixXmlUtf8): TDateTime;
begin
  Result := LandrixXmlParseCiiDateBuf(Utf8Ptr(S), Length(S));
end;

function LandrixXmlFormatCiiDate(Value: TDateTime; Format: Integer): TLandrixXmlUtf8;
var
  Parts: TLandrixXmlDateTime;
begin
  if (Format <> 102) and (Format <> 610) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument,
      'Unsupported CII date format ' + IntToStr(Format));
  Parts := LandrixXmlDateTimeToParts(Value);
  if Format = 102 then
    Result := ToUtf8(Pad(Parts.Year, 4) + Pad(Parts.Month, 2) + Pad(Parts.Day, 2))
  else
    Result := ToUtf8(Pad(Parts.Year, 4) + Pad(Parts.Month, 2));
end;

end.
