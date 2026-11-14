{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Internal unit of the XSLT processor (LandrixXmlXslt), not part of the
  documented API: format-date(), format-time() and format-dateTime()
  (XSLT 2.0 16.5) as Saxon HE formats them, in English (another language
  is named as Saxon names it: "[Language: en]" before the result).

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

{ Value: the canonical lexical form of an xs:date, xs:time or
  xs:dateTime (Kind); HasLanguage, HasCalendar: a language or calendar
  was given (an empty language Saxon names too, an empty calendar is
  FOFD1340). }
function XsltFormatDateTime(const Value: TLandrixXmlUtf8; Kind: TXsltDateKind;
  const Picture, Language, Calendar: TLandrixXmlUtf8; HasLanguage, HasCalendar: Boolean): TLandrixXmlUtf8;

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

end.
