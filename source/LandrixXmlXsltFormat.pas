{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Internal unit of the XSLT processor (LandrixXmlXslt), not part of the
  documented API: format-number() (XSLT 2.0 16.4) and format-date(),
  format-time() and format-dateTime() (XSLT 2.0 16.5) as Saxon HE formats
  them, in English (another language is named as Saxon names it:
  "[Language: en]" before the result).

  Components Y M D d F W H h P m s f Z z C E with decimal presentations
  (a format token of ASCII digits, its digits the minimum width; a year
  with two or more digits in it is cut to as many), roman numerals (I,
  i), names (N, n, Nn) and width modifiers. Words (W, w), ordinals (o),
  the week in the month (w) and other format tokens raise
  xecUnsupported; a malformed picture FOFD1340, a component the value
  does not have FOFD1350 (the codes Saxon gives). }

unit LandrixXmlXsltFormat;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  LandrixXmlBase;

type
  TXsltDateKind = (xdkDate, xdkTime, xdkDateTime);

  { an xsl:decimal-format: its characters and strings (UTF-8) }
  TXsltDecimalFormat = class
  public
    DecimalSeparator, GroupingSeparator, Infinity, MinusSign, NaN, Percent, PerMille, ZeroDigit, Digit,
      PatternSeparator: TLandrixXmlUtf8;
    { per property (PropertyIndex) the value and the import precedence of
      the declaration that set it (-1: the default), for XTSE1290 }
    Values: array[0..9] of TLandrixXmlUtf8;
    Precedences: array[0..9] of Integer;
    { the defaults of XSLT 2.0 }
    constructor Create;
    function PropertyIndex(const Name: TLandrixXmlUtf8): Integer;
  end;

{ Value: the canonical lexical form of an xs:date, xs:time or
  xs:dateTime (Kind); HasLanguage, HasCalendar: a language or calendar
  was given (an empty language Saxon names too, an empty calendar is
  FOFD1340). }
function XsltFormatDateTime(const Value: TLandrixXmlUtf8; Kind: TXsltDateKind;
  const Picture, Language, Calendar: TLandrixXmlUtf8; HasLanguage, HasCalendar: Boolean): TLandrixXmlUtf8;

{ format-number() (XSLT 2.0 16.4) as Saxon HE formats: Value is 'NaN',
  'INF', '-INF' or the lexical form of an xs:decimal, xs:integer or
  xs:double (its shortest decimal form, so a double is rounded as Saxon
  rounds it: half to even on those digits). Picture errors are FODF1310 (as Saxon);
  a zero digit other than 0 is not supported. }
function XsltFormatNumber(const Value: TLandrixXmlUtf8; const Picture: TLandrixXmlUtf8;
  DF: TXsltDecimalFormat; Scaled: Boolean): TLandrixXmlUtf8;
{ 100 or 1000 if the sub-picture for the sign (Negative) has a percent or
  per-mille sign, else 1: a double is multiplied as a double before it is
  formatted (Scaled), as Saxon does. Checks the picture (FODF1310). }
function XsltPictureScale(const Picture: TLandrixXmlUtf8; DF: TXsltDecimalFormat; Negative: Boolean): Integer;

implementation

uses
  LandrixXmlXPath;

const
  MonthNames: array[1..12] of string = ('January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December');
  DayNames: array[1..7] of string = ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday');
  { the forms of the day names Saxon chooses from, shortest first }
  DayForms: array[1..7] of string = ('M|Mo|Mon|Monday', 'Tu|Tue|Tues|Tuesday', 'W|We|Wed|Weds|Wednesday',
    'Th|Thu|Thur|Thurs|Thursday', 'F|Fr|Fri|Friday', 'Sa|Sat|Saturday', 'Su|Sun|Sunday');

type
  TDateParts = record
    HasDate, HasTime, HasZone: Boolean;
    Year, Month, Day, Hour, Minute, Second: Integer;
    { the digits after the decimal point, '' for none }
    Fraction: TLandrixXmlUtf8;
    { the offset in minutes }
    Zone: Integer;
  end;

procedure Fail(const Code, Msg: string);
begin
  raise ELandrixXmlXPathError.CreateXPath(Code, Msg);
end;

procedure Unsupported(const Msg: string);
begin
  raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT: ' + Msg + ' is not supported');
end;

function Digits(const S: TLandrixXmlUtf8; var I: Integer; N: Integer): Integer;
var
  K: Integer;
begin
  Result := 0;
  for K := 1 to N do
  begin
    if (I > Length(S)) or not (S[I] in ['0'..'9']) then
      Fail('FORG0001', 'not a valid date or time: "' + LandrixXmlUtf8ToString(S) + '"');
    Result := Result * 10 + Ord(S[I]) - Ord('0');
    Inc(I);
  end;
end;

{ the parts of a canonical lexical form }
function ParseValue(const S: TLandrixXmlUtf8; Kind: TXsltDateKind): TDateParts;
var
  I, Start: Integer;
  Negative: Boolean;
begin
  Result.HasDate := Kind <> xdkTime;
  Result.HasTime := Kind <> xdkDate;
  Result.HasZone := False;
  Result.Year := 0;
  Result.Month := 1;
  Result.Day := 1;
  Result.Hour := 0;
  Result.Minute := 0;
  Result.Second := 0;
  Result.Fraction := '';
  Result.Zone := 0;
  I := 1;
  if Result.HasDate then
  begin
    Negative := (I <= Length(S)) and (S[I] = '-');
    if Negative then
      Inc(I);
    Start := I;
    while (I <= Length(S)) and (S[I] in ['0'..'9']) do
      Inc(I);
    if I - Start < 4 then
      Fail('FORG0001', 'not a valid date: "' + LandrixXmlUtf8ToString(S) + '"');
    Result.Year := StrToInt(LandrixXmlUtf8ToString(Copy(S, Start, I - Start)));
    if Negative then
      Result.Year := -Result.Year;
    Inc(I);
    Result.Month := Digits(S, I, 2);
    Inc(I);
    Result.Day := Digits(S, I, 2);
    if Result.HasTime then
      Inc(I);
  end;
  if Result.HasTime then
  begin
    Result.Hour := Digits(S, I, 2);
    Inc(I);
    Result.Minute := Digits(S, I, 2);
    Inc(I);
    Result.Second := Digits(S, I, 2);
    if (I <= Length(S)) and (S[I] = '.') then
    begin
      Inc(I);
      Start := I;
      while (I <= Length(S)) and (S[I] in ['0'..'9']) do
        Inc(I);
      Result.Fraction := Copy(S, Start, I - Start);
    end;
  end;
  if I <= Length(S) then
  begin
    Result.HasZone := True;
    if S[I] <> 'Z' then
    begin
      Negative := S[I] = '-';
      Inc(I);
      Result.Zone := Digits(S, I, 2) * 60;
      Inc(I);
      Result.Zone := Result.Zone + Digits(S, I, 2);
      if Negative then
        Result.Zone := -Result.Zone;
    end;
  end;
end;

{ days since 1970-01-01 of a proleptic Gregorian date }
function DaysFromCivil(Y, M, D: Integer): Integer;
var
  Era, Yoe, Doy, Doe: Integer;
begin
  if M <= 2 then
    Dec(Y);
  if Y >= 0 then
    Era := Y div 400
  else
    Era := (Y - 399) div 400;
  Yoe := Y - Era * 400;
  if M > 2 then
    Doy := (153 * (M - 3) + 2) div 5 + D - 1
  else
    Doy := (153 * (M + 9) + 2) div 5 + D - 1;
  Doe := Yoe * 365 + Yoe div 4 - Yoe div 100 + Doy;
  Result := Era * 146097 + Doe - 719468;
end;

{ 1 = Monday ... 7 = Sunday }
function DayOfWeek(Y, M, D: Integer): Integer;
var
  Z: Integer;
begin
  Z := DaysFromCivil(Y, M, D);
  Result := ((Z + 3) mod 7 + 7) mod 7 + 1;
end;

function DayOfYear(Y, M, D: Integer): Integer;
begin
  Result := DaysFromCivil(Y, M, D) - DaysFromCivil(Y, 1, 1) + 1;
end;

function WeeksInYear(Y: Integer): Integer;

  { floor division (also for years before 1) }
  function FloorDiv(A, B: Integer): Integer;
  begin
    Result := A div B;
    if (A mod B <> 0) and (A < 0) then
      Dec(Result);
  end;

  function P(X: Integer): Integer;
  begin
    Result := ((X + FloorDiv(X, 4) - FloorDiv(X, 100) + FloorDiv(X, 400)) mod 7 + 7) mod 7;
  end;

begin
  if (P(Y) = 4) or (P(Y - 1) = 3) then
    Result := 53
  else
    Result := 52;
end;

{ the ISO 8601 week number }
function IsoWeek(Y, M, D: Integer): Integer;
begin
  Result := (DayOfYear(Y, M, D) - DayOfWeek(Y, M, D) + 10) div 7;
  if Result < 1 then
    Result := WeeksInYear(Y - 1)
  else if Result > WeeksInYear(Y) then
    Result := 1;
end;

function Roman(N: Integer): TLandrixXmlUtf8;
const
  Values: array[0..12] of Integer = (1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1);
  Symbols: array[0..12] of string = ('M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I');
var
  I: Integer;
begin
  Result := '';
  if (N <= 0) or (N > 9999) then
  begin
    Result := LandrixXmlStringToUtf8(IntToStr(N));
    Exit;
  end;
  for I := 0 to 12 do
    while N >= Values[I] do
    begin
      Result := Result + LandrixXmlStringToUtf8(Symbols[I]);
      Dec(N, Values[I]);
    end;
end;

function Upper8(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if Result[I] in ['a'..'z'] then
      Result[I] := AnsiChar(Ord(Result[I]) - 32);
end;

function Lower8(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if Result[I] in ['A'..'Z'] then
      Result[I] := AnsiChar(Ord(Result[I]) + 32);
end;

function Pad(const S: TLandrixXmlUtf8; Width: Integer; C: AnsiChar; Left: Boolean): TLandrixXmlUtf8;
var
  Fill: TLandrixXmlUtf8;
  I: Integer;
begin
  Result := S;
  if Length(Result) >= Width then
    Exit;
  Fill := '';
  SetLength(Fill, Width - Length(Result));
  for I := 1 to Length(Fill) do
    Fill[I] := C;
  if Left then
    Result := Fill + Result
  else
    Result := Result + Fill;
end;

{ the presentation of a name: N upper case, n lower case, Nn title case;
  the maximum width cuts, the minimum pads with spaces }
function NameValue(const Name, Token: TLandrixXmlUtf8; MinW, MaxW: Integer): TLandrixXmlUtf8;
begin
  if Token = 'N' then
    Result := Upper8(Name)
  else if Token = 'n' then
    Result := Lower8(Name)
  else
    Result := Name;
  if (MaxW > 0) and (Length(Result) > MaxW) then
    Result := Copy(Result, 1, MaxW);
  Result := Pad(Result, MinW, ' ', False);
end;

{ the name of day N within the maximum width as Saxon shortens it: the
  longest of its forms that fits, else the shortest }
function DayName(N, MaxW: Integer): TLandrixXmlUtf8;
var
  Forms, F: string;
  K: Integer;
begin
  Result := LandrixXmlStringToUtf8(DayNames[N]);
  if (MaxW <= 0) or (Length(Result) <= MaxW) then
    Exit;
  Forms := DayForms[N] + '|';
  Result := '';
  while Forms <> '' do
  begin
    K := Pos('|', Forms);
    F := Copy(Forms, 1, K - 1);
    Delete(Forms, 1, K);
    if (Result = '') or (Length(F) <= MaxW) then
      Result := LandrixXmlStringToUtf8(F);
  end;
end;

{ the name of month N within the maximum width: cut, but to three
  letters at least (as Saxon) }
function MonthName(N, MaxW: Integer): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(MonthNames[N]);
  if MaxW <= 0 then
    Exit;
  if MaxW < 3 then
    MaxW := 3;
  Result := Copy(Result, 1, MaxW);
end;

{ a number in a decimal format token (its digits the minimum width) or as
  a roman numeral }
function NumberValue(N: Integer; const Token: TLandrixXmlUtf8; MinW, MaxW: Integer; IsYear: Boolean): TLandrixXmlUtf8;
var
  I, Width: Integer;
begin
  if (Token = 'I') or (Token = 'i') then
  begin
    Result := Roman(N);
    if Token = 'i' then
      Result := Lower8(Result);
    Exit;
  end;
  Width := 0;
  for I := 1 to Length(Token) do
    if Token[I] in ['0'..'9'] then
      Inc(Width)
    else
      Unsupported('the format token "' + LandrixXmlUtf8ToString(Token) + '"');
  if Width = 0 then
    Unsupported('the format token "' + LandrixXmlUtf8ToString(Token) + '"');
  Result := LandrixXmlStringToUtf8(IntToStr(Abs(N)));
  { a year is cut to the width of a token with two digits or more, or to
    the maximum width }
  if IsYear and (MaxW < 0) and (Width >= 2) then
    MaxW := Width;
  if IsYear and (MaxW > 0) and (Length(Result) > MaxW) then
    Result := Copy(Result, Length(Result) - MaxW + 1, MaxW);
  if MinW > Width then
    Width := MinW;
  Result := Pad(Result, Width, '0', True);
  if N < 0 then
    Result := '-' + Result;
end;

{ a time zone: tokens "01:01" (the default), "00:00", "0000", "01", "0" }
function ZoneValue(Minutes: Integer; const Token: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  H, M, Colon, HourDigits: Integer;
  Sign: TLandrixXmlUtf8;
begin
  if Minutes < 0 then
    Sign := '-'
  else
    Sign := '+';
  H := Abs(Minutes) div 60;
  M := Abs(Minutes) mod 60;
  Colon := Pos(':', LandrixXmlUtf8ToString(Token));
  if Colon > 0 then
    HourDigits := Colon - 1
  else if Length(Token) >= 3 then
    { hours and minutes: H(H)MM }
    HourDigits := Length(Token) - 2
  else
    HourDigits := Length(Token);
  Result := Sign + Pad(LandrixXmlStringToUtf8(IntToStr(H)), HourDigits, '0', True);
  if Colon > 0 then
    Result := Result + ':' + Pad(LandrixXmlStringToUtf8(IntToStr(M)), 2, '0', True)
  else if Length(Token) >= 3 then
    Result := Result + Pad(LandrixXmlStringToUtf8(IntToStr(M)), 2, '0', True)
  else if M <> 0 then
    Result := Result + ':' + Pad(LandrixXmlStringToUtf8(IntToStr(M)), 2, '0', True);
end;

{ S as a decimal number of up to 6 digits, -1 if it is none }
function DecimalOf(const S: TLandrixXmlUtf8): Integer;
var
  I: Integer;
begin
  Result := -1;
  if (S = '') or (Length(S) > 6) then
    Exit;
  for I := 1 to Length(S) do
    if not (S[I] in ['0'..'9']) then
      Exit;
  Result := StrToInt(LandrixXmlUtf8ToString(S));
end;

{ one variable marker (without brackets and white space) }
function Marker(const Spec: TLandrixXmlUtf8; const D: TDateParts): TLandrixXmlUtf8;
var
  C: AnsiChar;
  Token, Width: TLandrixXmlUtf8;
  K, MinW, MaxW, N: Integer;
  MinS, MaxS: TLandrixXmlUtf8;
begin
  Result := '';
  if Spec = '' then
    Fail('FOFD1340', 'an empty variable marker in a picture');
  C := Spec[1];
  Token := Copy(Spec, 2, MaxInt);
  Width := '';
  K := Pos(',', LandrixXmlUtf8ToString(Token));
  if K > 0 then
  begin
    Width := Copy(Token, K + 1, MaxInt);
    Token := Copy(Token, 1, K - 1);
  end;
  { MaxW: -1 without a width modifier, 0 for "*" }
  MinW := 0;
  MaxW := -1;
  if K > 0 then
  begin
    K := Pos('-', LandrixXmlUtf8ToString(Width));
    if K > 0 then
    begin
      MinS := Copy(Width, 1, K - 1);
      MaxS := Copy(Width, K + 1, MaxInt);
    end
    else
    begin
      MinS := Width;
      MaxS := '*';
    end;
    MaxW := 0;
    if MinS <> '*' then
      MinW := DecimalOf(MinS);
    if MaxS <> '*' then
      MaxW := DecimalOf(MaxS);
    if (MinW < 0) or (MaxW < 0) or (MinS <> '*') and (MinW = 0) or (MaxS <> '*') and (MaxW = 0) or
      (MaxW > 0) and (MaxW < MinW) then
      Fail('FOFD1340', 'a bad width modifier "' + LandrixXmlUtf8ToString(Width) + '" in a picture');
  end;
  if (C in ['Y', 'M', 'D', 'd', 'F', 'W', 'w', 'C', 'E']) and not D.HasDate or
    (C in ['H', 'h', 'P', 'm', 's', 'f']) and not D.HasTime then
    Fail('FOFD1350', 'the component "' + LandrixXmlUtf8ToString(Copy(Spec, 1, 1)) + '" is not available');
  if (Token <> '') and (Token[Length(Token)] in ['o', 't', 'c']) and (Length(Token) > 1) then
  begin
    if Token[Length(Token)] = 'o' then
      Unsupported('ordinal numbers in a picture');
    if Token[Length(Token)] = 't' then
      Unsupported('the traditional modifier "t" in a picture');
    Token := Copy(Token, 1, Length(Token) - 1);
  end;
  if (Token = 'W') or (Token = 'w') or (Token = 'Ww') then
    Unsupported('numbers in words in a picture');
  case C of
    'Y', 'M', 'D', 'd', 'W', 'H', 'h', 'm', 's':
      begin
        case C of
          'Y': N := Abs(D.Year);
          'M': N := D.Month;
          'D': N := D.Day;
          'd': N := DayOfYear(D.Year, D.Month, D.Day);
          'W': N := IsoWeek(D.Year, D.Month, D.Day);
          'H': N := D.Hour;
          'h':
            begin
              N := D.Hour mod 12;
              if N = 0 then
                N := 12;
            end;
          'm': N := D.Minute;
        else
          N := D.Second;
        end;
        if (C = 'M') and ((Token = 'N') or (Token = 'n') or (Token = 'Nn')) then
          Result := NameValue(MonthName(N, MaxW), Token, MinW, -1)
        else
        begin
          if Token = '' then
          begin
            if C in ['m', 's'] then
              Token := '01'
            else
              Token := '1';
          end;
          Result := NumberValue(N, Token, MinW, MaxW, C = 'Y');
        end;
      end;
    'F':
      begin
        N := DayOfWeek(D.Year, D.Month, D.Day);
        if Token = '' then
          Token := 'Nn';
        if (Token = 'N') or (Token = 'n') or (Token = 'Nn') then
          Result := NameValue(DayName(N, MaxW), Token, MinW, -1)
        else
          Result := NumberValue(N, Token, MinW, MaxW, False);
      end;
    'P':
      begin
        { a.m./p.m., upper case for N and Nn as Saxon writes them }
        if MaxW >= 0 then
          Unsupported('a width modifier for am/pm');
        if (Token = '') or (Token = 'n') then
          Token := 'n'
        else if (Token = 'N') or (Token = 'Nn') then
          Token := 'N'
        else
          Unsupported('the format token "' + LandrixXmlUtf8ToString(Token) + '" for am/pm');
        if D.Hour < 12 then
          Result := NameValue('a.m.', Token, 0, -1)
        else
          Result := NameValue('p.m.', Token, 0, -1);
      end;
    'f':
      begin
        { the value's digits (microseconds, as Saxon keeps them) without
          trailing zeros, padded with zeros to the token's digits and the
          minimum width, cut to the maximum }
        Result := Copy(D.Fraction, 1, 6);
        while (Length(Result) > 1) and (Result[Length(Result)] = '0') do
          Delete(Result, Length(Result), 1);
        if Result = '' then
          Result := '0';
        N := 0;
        if (Token <> '') and (Token <> '1') then
          for K := 1 to Length(Token) do
            if (Token[K] = '0') or (Token[K] = '1') and (K = Length(Token)) then
              Inc(N)
            else
              Unsupported('the format token "' + LandrixXmlUtf8ToString(Token) + '" for fractional seconds');
        { at least the token's digits and the minimum width; at most the
          maximum width (not below the token's digits), without one the
          token's digits when it has two or more (as Saxon formats) }
        if MinW > N then
          Result := Pad(Result, MinW, '0', False)
        else
          Result := Pad(Result, N, '0', False);
        if (MaxW > 0) and (MaxW < N) then
          MaxW := N
        else if (MaxW < 0) and (N >= 2) then
          MaxW := N;
        if (MaxW > 0) and (Length(Result) > MaxW) then
          Result := Copy(Result, 1, MaxW);
      end;
    'Z', 'z':
      begin
        Result := '';
        if not D.HasZone then
          Exit;
        if MaxW >= 0 then
          Unsupported('a width modifier for a time zone');
        if Token = '' then
          Token := '01:01';
        for K := 1 to Length(Token) do
          if not (Token[K] in ['0'..'9', ':']) then
            Unsupported('the time zone format "' + LandrixXmlUtf8ToString(Token) + '"');
        Result := ZoneValue(D.Zone, Token);
        if C = 'z' then
          Result := 'GMT' + Result;
      end;
    'C':
      Result := NameValue('Gregorian', 'Nn', MinW, MaxW);
    'E':
      if D.Year < 0 then
        Result := 'BC'
      else
        Result := 'AD';
  else
    if C = 'w' then
      Unsupported('the week in the month in a picture');
    Fail('FOFD1340', 'an unknown component "' + LandrixXmlUtf8ToString(Copy(Spec, 1, 1)) + '" in a picture');
  end;
end;

function XsltFormatDateTime(const Value: TLandrixXmlUtf8; Kind: TXsltDateKind;
  const Picture, Language, Calendar: TLandrixXmlUtf8; HasLanguage, HasCalendar: Boolean): TLandrixXmlUtf8;
var
  D: TDateParts;
  I, K, Close: Integer;
  Spec: TLandrixXmlUtf8;
begin
  D := ParseValue(Value, Kind);
  Result := '';
  if HasCalendar and (Calendar = '') then
    Fail('FOFD1340', 'an empty calendar name');
  if HasCalendar and (Calendar <> 'AD') and (Calendar <> 'ISO') then
    Unsupported('the calendar "' + LandrixXmlUtf8ToString(Calendar) + '"');
  { Saxon HE has English only and says so }
  if HasLanguage and (Language <> 'en') and (Copy(Language, 1, 3) <> 'en-') then
    Result := '[Language: en]';
  I := 1;
  while I <= Length(Picture) do
  begin
    if Picture[I] = '[' then
    begin
      if (I < Length(Picture)) and (Picture[I + 1] = '[') then
      begin
        Result := Result + '[';
        Inc(I, 2);
        Continue;
      end;
      Close := I + 1;
      while (Close <= Length(Picture)) and (Picture[Close] <> ']') do
        Inc(Close);
      if Close > Length(Picture) then
        Fail('FOFD1340', 'a "[" without "]" in a picture');
      Spec := '';
      for K := I + 1 to Close - 1 do
        if not (Picture[K] in [#9, #10, #13, ' ']) then
          Spec := Spec + Copy(Picture, K, 1);
      Result := Result + Marker(Spec, D);
      I := Close + 1;
    end
    else if Picture[I] = ']' then
    begin
      if (I < Length(Picture)) and (Picture[I + 1] = ']') then
      begin
        Result := Result + ']';
        Inc(I, 2);
        Continue;
      end;
      Fail('FOFD1340', 'a "]" without "[" in a picture');
    end
    else
    begin
      Result := Result + Copy(Picture, I, 1);
      Inc(I);
    end;
  end;
end;

{ --- format-number --------------------------------------------------------- }

constructor TXsltDecimalFormat.Create;
var
  I: Integer;
begin
  inherited Create;
  DecimalSeparator := '.';
  GroupingSeparator := ',';
  Infinity := 'Infinity';
  MinusSign := '-';
  NaN := 'NaN';
  Percent := '%';
  { U+2030 in UTF-8 }
  PerMille := '';
  SetLength(PerMille, 3);
  PerMille[1] := AnsiChar($E2);
  PerMille[2] := AnsiChar($80);
  PerMille[3] := AnsiChar($B0);
  ZeroDigit := '0';
  Digit := '#';
  PatternSeparator := ';';
  for I := 0 to 9 do
    Precedences[I] := -1;
end;

function TXsltDecimalFormat.PropertyIndex(const Name: TLandrixXmlUtf8): Integer;
begin
  if Name = 'decimal-separator' then
    Result := 0
  else if Name = 'grouping-separator' then
    Result := 1
  else if Name = 'infinity' then
    Result := 2
  else if Name = 'minus-sign' then
    Result := 3
  else if Name = 'NaN' then
    Result := 4
  else if Name = 'percent' then
    Result := 5
  else if Name = 'per-mille' then
    Result := 6
  else if Name = 'zero-digit' then
    Result := 7
  else if Name = 'digit' then
    Result := 8
  else
    Result := 9;
end;

{ the characters of S (UTF-8 sequences) }
function Chars(const S: TLandrixXmlUtf8): TLandrixXmlUtf8Array;
var
  I, N, K: Integer;
begin
  Result := nil;
  I := 1;
  while I <= Length(S) do
  begin
    N := 1;
    if Ord(S[I]) >= $F0 then
      N := 4
    else if Ord(S[I]) >= $E0 then
      N := 3
    else if Ord(S[I]) >= $C0 then
      N := 2;
    K := Integer(Length(Result));
    SetLength(Result, K + 1);
    Result[K] := Copy(S, I, N);
    Inc(I, N);
  end;
end;

{ Value as a sign and decimal digits: Value is the lexical form of an
  xs:decimal, an xs:integer or an xs:double (also with an exponent, as
  XPath writes doubles). }
procedure SplitNumber(const Value: TLandrixXmlUtf8; out Negative: Boolean; out IntPart, FracPart: TLandrixXmlUtf8);
var
  I, E, Exp: Integer;
  Mantissa, Digits: TLandrixXmlUtf8;
  Point: Integer;
begin
  Negative := (Value <> '') and (Value[1] = '-');
  I := 1;
  if Negative or (Value <> '') and (Value[1] = '+') then
    I := 2;
  E := Pos('E', LandrixXmlUtf8ToString(Value));
  if E = 0 then
    E := Pos('e', LandrixXmlUtf8ToString(Value));
  Exp := 0;
  if E > 0 then
  begin
    Mantissa := Copy(Value, I, E - I);
    Exp := StrToInt(LandrixXmlUtf8ToString(Copy(Value, E + 1, MaxInt)));
  end
  else
    Mantissa := Copy(Value, I, MaxInt);
  Point := Pos('.', LandrixXmlUtf8ToString(Mantissa));
  if Point = 0 then
  begin
    Digits := Mantissa;
    Point := Length(Mantissa) + 1;
  end
  else
    Digits := Copy(Mantissa, 1, Point - 1) + Copy(Mantissa, Point + 1, MaxInt);
  { the decimal point after Point - 1 + Exp digits }
  Point := Point - 1 + Exp;
  while Point < 0 do
  begin
    Digits := '0' + Digits;
    Inc(Point);
  end;
  while Point > Length(Digits) do
    Digits := Digits + '0';
  IntPart := Copy(Digits, 1, Point);
  FracPart := Copy(Digits, Point + 1, MaxInt);
  while (Length(IntPart) > 0) and (IntPart[1] = '0') do
    Delete(IntPart, 1, 1);
  while (Length(FracPart) > 0) and (FracPart[Length(FracPart)] = '0') do
    Delete(FracPart, Length(FracPart), 1);
end;

{ Rounds IntPart.FracPart to Places fraction digits, half to even }
procedure RoundHalfEven(var IntPart, FracPart: TLandrixXmlUtf8; Places: Integer);
var
  Digits: TLandrixXmlUtf8;
  N, I: Integer;
  Up: Boolean;
  Rest: TLandrixXmlUtf8;
begin
  if Length(FracPart) <= Places then
    Exit;
  Rest := Copy(FracPart, Places + 1, MaxInt);
  Digits := IntPart + Copy(FracPart, 1, Places);
  if Rest[1] > '5' then
    Up := True
  else if Rest[1] < '5' then
    Up := False
  else
  begin
    Up := False;
    for I := 2 to Length(Rest) do
      if Rest[I] <> '0' then
        Up := True;
    if not Up then
      Up := (Digits <> '') and (Odd(Ord(Digits[Length(Digits)]) - Ord('0')));
  end;
  if Up then
  begin
    I := Length(Digits);
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
  N := Length(Digits) - Places;
  IntPart := Copy(Digits, 1, N);
  FracPart := Copy(Digits, N + 1, MaxInt);
  while (Length(IntPart) > 0) and (IntPart[1] = '0') do
    Delete(IntPart, 1, 1);
  while (Length(FracPart) > 0) and (FracPart[Length(FracPart)] = '0') do
    Delete(FracPart, Length(FracPart), 1);
end;

type
  TSubPicture = record
    Prefix, Suffix: TLandrixXmlUtf8;
    MinInt, MinFrac, MaxFrac: Integer;
    { grouping positions of the integer part (digits to their right) and
      of the fraction part (digits to their left) }
    IntGroups, FracGroups: array of Integer;
    Percent, PerMille: Boolean;
  end;

procedure PictureError(const Picture: TLandrixXmlUtf8; const Why: string);
begin
  raise ELandrixXmlXPathError.CreateXPath('FODF1310', 'format-number(): the picture "' +
    LandrixXmlUtf8ToString(Picture) + '" ' + Why);
end;

function ParseSubPicture(const P: TLandrixXmlUtf8Array; First, Last: Integer; DF: TXsltDecimalFormat;
  const Picture: TLandrixXmlUtf8): TSubPicture;
var
  I, A, Z, Point, Digits: Integer;
  C: TLandrixXmlUtf8;
  AfterZero: Boolean;

  function Active(const X: TLandrixXmlUtf8): Boolean;
  begin
    Result := (X = DF.DecimalSeparator) or (X = DF.GroupingSeparator) or (X = DF.Digit) or
      ((Length(X) = 1) and (X[1] in ['0'..'9']));
  end;

begin
  Result.Prefix := '';
  Result.Suffix := '';
  Result.MinInt := 0;
  Result.MinFrac := 0;
  Result.MaxFrac := 0;
  Result.IntGroups := nil;
  Result.FracGroups := nil;
  Result.Percent := False;
  Result.PerMille := False;
  A := First;
  while (A <= Last) and not Active(P[A]) do
    Inc(A);
  Z := Last;
  while (Z >= A) and not Active(P[Z]) do
    Dec(Z);
  if A > Z then
    PictureError(Picture, 'has no digit');
  for I := First to A - 1 do
    Result.Prefix := Result.Prefix + P[I];
  for I := Z + 1 to Last do
    Result.Suffix := Result.Suffix + P[I];
  for I := First to Last do
  begin
    if (P[I] = DF.Percent) or (P[I] = DF.PerMille) then
    begin
      if Result.Percent or Result.PerMille then
        PictureError(Picture, 'has more than one percent or per-mille sign');
      if (I >= A) and (I <= Z) then
        PictureError(Picture, 'has a percent or per-mille sign among the digits');
      Result.Percent := P[I] = DF.Percent;
      Result.PerMille := P[I] = DF.PerMille;
    end;
  end;
  Point := -1;
  for I := A to Z do
  begin
    if not Active(P[I]) then
      PictureError(Picture, 'has a passive character among the digits');
    if P[I] = DF.DecimalSeparator then
    begin
      if Point >= 0 then
        PictureError(Picture, 'has two decimal separators');
      Point := I;
    end;
  end;
  if Point < 0 then
    Point := Z + 1;
  Digits := 0;
  for I := A to Z do
    if (P[I] = DF.Digit) or (Length(P[I]) = 1) and (P[I][1] in ['0'..'9']) then
      Inc(Digits);
  if Digits = 0 then
    PictureError(Picture, 'has no digit');
  if (Point + 1 <= Z) and (P[Point + 1] = DF.GroupingSeparator) then
    PictureError(Picture, 'has a grouping separator next to the decimal separator');
  if (Point - 1 >= A) and (P[Point - 1] = DF.GroupingSeparator) then
    PictureError(Picture, 'has a grouping separator at the end of the integer part');
  for I := A to Z - 1 do
    if (P[I] = DF.GroupingSeparator) and (P[I + 1] = DF.GroupingSeparator) then
      PictureError(Picture, 'has two grouping separators in a row');
  { the integer part }
  AfterZero := False;
  Digits := 0;
  for I := Point - 1 downto A do
  begin
    C := P[I];
    if C = DF.GroupingSeparator then
    begin
      if (I = Point - 1) and (Point <= Z) then
        PictureError(Picture, 'has a grouping separator next to the decimal separator');
      SetLength(Result.IntGroups, Length(Result.IntGroups) + 1);
      Result.IntGroups[High(Result.IntGroups)] := Digits;
    end
    else
    begin
      Inc(Digits);
      if C = DF.Digit then
      begin
        AfterZero := True;
        Continue;
      end;
      if AfterZero then
        PictureError(Picture, 'has a "0" before a "#" in the integer part');
      Inc(Result.MinInt);
    end;
  end;
  { the fraction part }
  Digits := 0;
  AfterZero := False;
  for I := Point + 1 to Z do
  begin
    C := P[I];
    if C = DF.GroupingSeparator then
    begin
      SetLength(Result.FracGroups, Length(Result.FracGroups) + 1);
      Result.FracGroups[High(Result.FracGroups)] := Digits;
    end
    else
    begin
      Inc(Digits);
      Inc(Result.MaxFrac);
      if C = DF.Digit then
        AfterZero := True
      else
      begin
        if AfterZero then
          PictureError(Picture, 'has a "0" after a "#" in the fraction part');
        Inc(Result.MinFrac);
      end;
    end;
  end;
  if (Result.MinInt = 0) and (Result.MaxFrac = 0) then
    Result.MinInt := 1
  else if (Result.MinInt = 0) and (Result.MinFrac = 0) then
    Result.MinFrac := 1;
end;

{ the integer digits with grouping separators }
function Group(const Digits: TLandrixXmlUtf8; const Positions: array of Integer; const Sep: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I, K, N, Every: Integer;
  Regular, Insert: Boolean;
begin
  Result := Digits;
  N := Integer(Length(Positions));
  if N = 0 then
    Exit;
  { regular: the positions are n, 2n, 3n, ... (then repeated) }
  Every := Positions[0];
  for I := 1 to N - 1 do
    if Positions[I] < Every then
      Every := Positions[I];
  Regular := Every > 0;
  if Regular then
    for I := 0 to N - 1 do
      if Positions[I] mod Every <> 0 then
        Regular := False;
  if Regular then
    for K := 1 to N do
    begin
      Insert := False;
      for I := 0 to N - 1 do
        if Positions[I] = K * Every then
          Insert := True;
      if not Insert then
        Regular := False;
    end;
  Result := '';
  for I := Length(Digits) downto 1 do
  begin
    K := Length(Digits) - I;
    Insert := False;
    if K > 0 then
    begin
      if Regular then
        Insert := K mod Every = 0
      else
        for N := 0 to Integer(High(Positions)) do
          if Positions[N] = K then
            Insert := True;
    end;
    if Insert then
      Result := Sep + Result;
    Result := Copy(Digits, I, 1) + Result;
  end;
end;

{ the sub-picture for the sign: both are checked }
function ChooseSubPicture(const Picture: TLandrixXmlUtf8; DF: TXsltDecimalFormat; Negative: Boolean;
  out HasNegative: Boolean): TSubPicture;
var
  P: TLandrixXmlUtf8Array;
  I, Sep: Integer;
  Other: TSubPicture;
begin
  if DF.ZeroDigit <> '0' then
    raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT: a zero digit other than 0 is not supported');
  P := Chars(Picture);
  Sep := -1;
  for I := 0 to Integer(Length(P)) - 1 do
    if P[I] = DF.PatternSeparator then
    begin
      if Sep >= 0 then
        PictureError(Picture, 'has two pattern separators');
      Sep := I;
    end;
  HasNegative := Sep >= 0;
  if Sep < 0 then
    Result := ParseSubPicture(P, 0, Integer(Length(P)) - 1, DF, Picture)
  else
  begin
    Result := ParseSubPicture(P, 0, Sep - 1, DF, Picture);
    Other := ParseSubPicture(P, Sep + 1, Integer(Length(P)) - 1, DF, Picture);
    if Negative then
      Result := Other;
  end;
end;

function XsltPictureScale(const Picture: TLandrixXmlUtf8; DF: TXsltDecimalFormat; Negative: Boolean): Integer;
var
  Sub: TSubPicture;
  HasNegative: Boolean;
begin
  Sub := ChooseSubPicture(Picture, DF, Negative, HasNegative);
  Result := 1;
  if Sub.Percent then
    Result := 100
  else if Sub.PerMille then
    Result := 1000;
end;

function XsltFormatNumber(const Value: TLandrixXmlUtf8; const Picture: TLandrixXmlUtf8;
  DF: TXsltDecimalFormat; Scaled: Boolean): TLandrixXmlUtf8;
var
  I, Sep: Integer;
  Sub: TSubPicture;
  Negative, HasNegative: Boolean;
  IntPart, FracPart, Frac: TLandrixXmlUtf8;
begin
  Negative := (Value <> '') and (Value[1] = '-');
  { the picture is checked also for NaN }
  Sub := ChooseSubPicture(Picture, DF, Negative, HasNegative);
  if Value = 'NaN' then
  begin
    Result := DF.NaN;
    Exit;
  end;
  if (Value = 'INF') or (Value = '-INF') then
  begin
    Result := Sub.Prefix + DF.Infinity + Sub.Suffix;
    if Negative and not HasNegative then
      Result := DF.MinusSign + Result;
    Exit;
  end;
  SplitNumber(Value, Negative, IntPart, FracPart);
  { percent and per mille: the decimal point moved (a double the caller
  multiplied already) }
  if (Sub.Percent or Sub.PerMille) and not Scaled then
  begin
    if Sub.Percent then
      I := 2
    else
      I := 3;
    while I > 0 do
    begin
      if FracPart <> '' then
      begin
        IntPart := IntPart + Copy(FracPart, 1, 1);
        Delete(FracPart, 1, 1);
      end
      else
        IntPart := IntPart + '0';
      Dec(I);
    end;
    while (Length(IntPart) > 0) and (IntPart[1] = '0') do
      Delete(IntPart, 1, 1);
  end;
  RoundHalfEven(IntPart, FracPart, Sub.MaxFrac);
  while Length(IntPart) < Sub.MinInt do
    IntPart := '0' + IntPart;
  while Length(FracPart) < Sub.MinFrac do
    FracPart := FracPart + '0';
  IntPart := Group(IntPart, Sub.IntGroups, DF.GroupingSeparator);
  Frac := FracPart;
  if Length(Sub.FracGroups) > 0 then
  begin
    Frac := '';
    for I := 1 to Length(FracPart) do
    begin
      for Sep := 0 to Integer(High(Sub.FracGroups)) do
        if (Sub.FracGroups[Sep] = I - 1) and (I > 1) then
          Frac := Frac + DF.GroupingSeparator;
      Frac := Frac + Copy(FracPart, I, 1);
    end;
  end;
  Result := Sub.Prefix + IntPart;
  if Frac <> '' then
    Result := Result + DF.DecimalSeparator + Frac;
  Result := Result + Sub.Suffix;
  if Negative and not HasNegative then
    Result := DF.MinusSign + Result;
end;

end.
