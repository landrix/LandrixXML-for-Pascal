{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Part of LandrixXmlXPathEval: operations on atomic values (string value,
  effective boolean value, comparisons, arithmetic, casts). Included in
  the implementation section. }

function AtomicString(const Item: TLandrixXmlXPathItem): TLandrixXmlUtf8;
begin
  case BasicKind(Item.Kind) of
    xikBoolean:
      if ItemBoolean(Item) then
        Result := 'true'
      else
        Result := 'false';
    xikInteger, xikDecimal:
      Result := LandrixXmlFormatDecimal(ItemDecimal(Item));
    xikDouble:
      Result := LandrixXmlDoubleFormat(ItemDouble(Item));
  else
    Result := Item.Text;
  end;
end;

{ fn:boolean, the effective boolean value. }
function SequenceBoolean(const S: TLandrixXmlXPathSequence): Boolean;
begin
  Result := False;
  if S.Count = 0 then
    Exit;
  if S.Items[0].Kind = xikNode then
  begin
    Result := True;
    Exit;
  end;
  if S.Count > 1 then
    Fail('FORG0006', 'the effective boolean value of a sequence of several atomic values');
  case BasicKind(S.Items[0].Kind) of
    xikBoolean:
      Result := ItemBoolean(S.Items[0]);
    xikString, xikUntypedAtomic, xikAnyUri:
      Result := S.Items[0].Text <> '';
    xikInteger, xikDecimal:
      Result := not LandrixXmlDecimalIsZero(ItemDecimal(S.Items[0]));
    xikDouble:
      Result := not LandrixXmlDoubleIsZero(ItemDouble(S.Items[0])) and
        not LandrixXmlDoubleIsNaN(ItemDouble(S.Items[0]));
  else
    Fail('FORG0006', 'no effective boolean value for ' + KindName(S.Items[0].Kind));
  end;
end;

function ToDouble(const Item: TLandrixXmlXPathItem): TLandrixXmlDouble;
begin
  if Item.Kind = xikDouble then
    Result := ItemDouble(Item)
  else
    Result := LandrixXmlDoubleFromDecimal(ItemDecimal(Item));
end;

function NumericEqualsInteger(const Item: TLandrixXmlXPathItem; Value: Integer): Boolean;
begin
  if Item.Kind = xikDouble then
    Result := LandrixXmlDoubleCompare(ItemDouble(Item), LandrixXmlDoubleFromInt64(Value)) = 0
  else
    Result := LandrixXmlDecimalCompare(ItemDecimal(Item), LandrixXmlDecimalFromInt64(Value)) = 0;
end;

{ untypedAtomic or a string as xs:double, as Saxon parses it; XPath 2.0
  uses the lexical forms of XML Schema 1.0, which has no "+INF". }
function ParseDouble(const S: TLandrixXmlUtf8; Xp20: Boolean): TLandrixXmlDouble;
begin
  if not LandrixXmlDoubleTryParse(Trimmed(S), Result) or (Xp20 and (Trimmed(S) = '+INF')) then
    Fail('FORG0001', 'cannot convert ''' + LandrixXmlEscapeForMessage(S, 60) + ''' to xs:double');
end;

function DateKindPrimitive(Kind: TLandrixXmlXPathItemKind): TLandrixXmlXsdPrimitive;
begin
  case Kind of
    xikDate: Result := xspDate;
    xikDateTime: Result := xspDateTime;
  else
    Result := xspTime;
  end;
end;

function Pad(Value, Digits: Integer): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(IntToStr(Value));
  while Length(Result) < Digits do
    Result := '0' + Result;
end;

{ The canonical lexical form XPath writes: fraction digits without
  trailing zeros, time zone Z for +00:00. }
function DateText(const D: TLandrixXmlXsdDateTime; Kind: TLandrixXmlXPathItemKind): TLandrixXmlUtf8;
var
  Seconds: TLandrixXmlUtf8;
  Tz: Integer;
begin
  Result := '';
  if Kind in [xikDate, xikDateTime] then
  begin
    if D.Year < 0 then
      Result := '-' + Pad(-D.Year, 4)
    else
      Result := Pad(D.Year, 4);
    Result := Result + '-' + Pad(D.Month, 2) + '-' + Pad(D.Day, 2);
  end;
  if Kind = xikDateTime then
    Result := Result + 'T';
  if Kind in [xikDateTime, xikTime] then
  begin
    Seconds := LandrixXmlFormatDecimal(D.Second);
    if (Length(Seconds) = 1) or ((Length(Seconds) > 1) and (Seconds[2] = '.')) then
      Seconds := '0' + Seconds;
    Result := Result + Pad(D.Hour, 2) + ':' + Pad(D.Minute, 2) + ':' + Seconds;
  end;
  if D.HasTimeZone then
  begin
    Tz := D.TimeZone;
    if Tz = 0 then
      Result := Result + 'Z'
    else
    begin
      if Tz < 0 then
      begin
        Result := Result + '-';
        Tz := -Tz;
      end
      else
        Result := Result + '+';
      Result := Result + Pad(Tz div 60, 2) + ':' + Pad(Tz mod 60, 2);
    end;
  end;
end;

{ 24:00:00 is 00:00:00 (of the next day for xs:dateTime). }
procedure NormalizeMidnight(var D: TLandrixXmlXsdDateTime; Kind: TLandrixXmlXPathItemKind);
var
  Days: Integer;
begin
  if D.Hour <> 24 then
    Exit;
  D.Hour := 0;
  if Kind <> xikDateTime then
    Exit;
  Inc(D.Day);
  case D.Month of
    4, 6, 9, 11: Days := 30;
    2:
      if (D.Year mod 4 = 0) and ((D.Year mod 100 <> 0) or (D.Year mod 400 = 0)) then
        Days := 29
      else
        Days := 28;
  else
    Days := 31;
  end;
  if D.Day > Days then
  begin
    D.Day := 1;
    Inc(D.Month);
    if D.Month > 12 then
    begin
      D.Month := 1;
      Inc(D.Year);
    end;
  end;
end;

function ParseDateKind(const S: TLandrixXmlUtf8; Kind: TLandrixXmlXPathItemKind): TLandrixXmlXPathItem;
var
  T: TLandrixXmlXsdSimpleType;
  V: TLandrixXmlXsdValue;
  E: TLandrixXmlXsdError;
  Name: TLandrixXmlUtf8;
  D: TLandrixXmlXsdDateTime;
begin
  case Kind of
    xikDate: Name := 'date';
    xikDateTime: Name := 'dateTime';
  else
    Name := 'time';
  end;
  T := LandrixXmlXsdBuiltinType(Name);
  if not T.Validate(S, V, E) then
    Fail('FORG0001', 'cannot convert ''' + LandrixXmlEscapeForMessage(S, 60) + ''' to xs:' +
      LandrixXmlUtf8ToString(Name));
  D := V.DateTime;
  NormalizeMidnight(D, Kind);
  Result := DateItem(Kind, D, DateText(D, Kind));
end;

function CompareDates(const A, B: TLandrixXmlXPathItem): Integer;
var
  VA, VB: TLandrixXmlXsdValue;
begin
  VA.MemberType := nil;
  VB.MemberType := nil;
  VA.Primitive := DateKindPrimitive(A.Kind);
  VB.Primitive := DateKindPrimitive(B.Kind);
  VA.DateTime := ItemDateTime(A);
  VB.DateTime := ItemDateTime(B);
  Result := LandrixXmlXsdCompareValues(VA, VB);
  if Result = LandrixXmlXsdIncomparable then
    Fail('FOER0000', 'comparing ' + KindName(A.Kind) + ' values with and without time zone is not supported');
end;

{ The result of a comparison from an ordering (-1, 0, 1; 2 = unordered). }
function Holds(Order: Integer; Op: TLandrixXmlXPathCompare): Boolean;
begin
  if Order = 2 then
  begin
    Result := Op = xpcNe;
    Exit;
  end;
  case Op of
    xpcEq: Result := Order = 0;
    xpcNe: Result := Order <> 0;
    xpcLt: Result := Order < 0;
    xpcLe: Result := Order <= 0;
    xpcGt: Result := Order > 0;
  else
    Result := Order >= 0;
  end;
end;

function CompareNumbers(const A, B: TLandrixXmlXPathItem): Integer;
begin
  if (A.Kind = xikDouble) or (B.Kind = xikDouble) then
  begin
    Result := LandrixXmlDoubleCompare(ToDouble(A), ToDouble(B));
    if Result = LandrixXmlDoubleUnordered then
      Result := 2;
  end
  else
    Result := LandrixXmlDecimalCompare(ItemDecimal(A), ItemDecimal(B));
end;

function CompareStrings(const A, B: TLandrixXmlUtf8): Integer;
begin
  { UTF-8 byte order is code point order }
  if A = B then
    Result := 0
  else if A < B then
    Result := -1
  else
    Result := 1;
end;

{ --- durations ------------------------------------------------------------ }

{ The limits are Saxon's: every number of the lexical form fits into 31
  bits, the months too, the seconds into 63 bits, at most nine fraction
  digits (ten are read, the tenth dropped). }

function Int64Text(V: Int64): TLandrixXmlUtf8;
begin
  { not IntToStr: Delphi 7 computes it on the x87 }
  Result := LandrixXmlFormatDecimal(LandrixXmlDecimalFromInt64(V));
end;

{ A / B (B not zero) rounded to Digits fraction digits; Mode is xdrDown,
  xdrHalfCeiling or xdrHalfEven. }
function DivideRounded(const A, B: TLandrixXmlDecimal; Digits: Integer;
  Mode: TLandrixXmlDecimalRounding): TLandrixXmlDecimal;
var
  X, Q, R: TLandrixXmlDecimal;
  C, Sign: Integer;
  Away: Boolean;
begin
  X := LandrixXmlDecimalMultiplyPow10(A, Digits);
  Q := LandrixXmlDecimalIntegerQuotient(X, B);
  R := LandrixXmlDecimalSubtract(X, LandrixXmlDecimalMultiply(Q, B));
  if not LandrixXmlDecimalIsZero(R) and (Mode <> xdrDown) then
  begin
    Sign := LandrixXmlDecimalSign(X) * LandrixXmlDecimalSign(B);
    C := LandrixXmlDecimalCompare(LandrixXmlDecimalAbs(LandrixXmlDecimalAdd(R, R)), LandrixXmlDecimalAbs(B));
    if C <> 0 then
      Away := C > 0
    else if Mode = xdrHalfCeiling then
      Away := Sign > 0
    else
      Away := not LandrixXmlDecimalIsZero(LandrixXmlDecimalModulo(Q, LandrixXmlDecimalFromInt64(2)));
    if Away then
      Q := LandrixXmlDecimalAdd(Q, LandrixXmlDecimalFromInt64(Sign));
  end;
  Result := LandrixXmlDecimalMultiplyPow10(Q, -Digits);
end;

{ The canonical lexical form: P, then years, months, days, T, hours,
  minutes and seconds where not zero; PT0S (P0M for
  xs:yearMonthDuration) for zero. }
function DurationText(Kind: TLandrixXmlXPathItemKind; Months: Integer;
  const Seconds: TLandrixXmlDecimal): TLandrixXmlUtf8;
var
  M, Whole: Int64;
  Abs, Fraction: TLandrixXmlDecimal;
  Time: TLandrixXmlUtf8;
begin
  M := Months;
  if M < 0 then
    M := -M;
  Abs := LandrixXmlDecimalAbs(Seconds);
  if not LandrixXmlDecimalTryToInt64(LandrixXmlDecimalRound(Abs, 0, xdrDown), Whole) then
    Whole := 0;
  Fraction := LandrixXmlDecimalSubtract(Abs, LandrixXmlDecimalFromInt64(Whole));
  if (M = 0) and LandrixXmlDecimalIsZero(Abs) then
  begin
    if Kind = xikYearMonthDuration then
      Result := 'P0M'
    else
      Result := 'PT0S';
    Exit;
  end;
  Result := 'P';
  if M div 12 > 0 then
    Result := Result + Int64Text(M div 12) + 'Y';
  if M mod 12 > 0 then
    Result := Result + Int64Text(M mod 12) + 'M';
  if Whole div 86400 > 0 then
    Result := Result + Int64Text(Whole div 86400) + 'D';
  Time := '';
  if Whole mod 86400 div 3600 > 0 then
    Time := Time + Int64Text(Whole mod 86400 div 3600) + 'H';
  if Whole mod 3600 div 60 > 0 then
    Time := Time + Int64Text(Whole mod 3600 div 60) + 'M';
  if (Whole mod 60 > 0) or not LandrixXmlDecimalIsZero(Fraction) then
    Time := Time + LandrixXmlFormatDecimal(LandrixXmlDecimalAdd(LandrixXmlDecimalFromInt64(Whole mod 60),
      Fraction)) + 'S';
  if Time <> '' then
    Result := Result + 'T' + Time;
  if (Months < 0) or (LandrixXmlDecimalSign(Seconds) < 0) then
    Result := '-' + Result;
end;

{ A duration of Kind (xs:yearMonthDuration keeps only the months,
  xs:dayTimeDuration only the seconds); FODT0002 beyond the limits. }
function DurationItem(Kind: TLandrixXmlXPathItemKind; const Months, Seconds: TLandrixXmlDecimal): TLandrixXmlXPathItem;
var
  M64, Whole: Int64;
  M: Integer;
  S: TLandrixXmlDecimal;
begin
  M := 0;
  S := LandrixXmlDecimalZero;
  if Kind <> xikDayTimeDuration then
  begin
    if not LandrixXmlDecimalTryToInt64(Months, M64) or (M64 > High(Integer)) or (M64 < -High(Integer)) then
      Fail('FODT0002', 'the duration is too large');
    M := Integer(M64);
  end;
  if Kind <> xikYearMonthDuration then
  begin
    S := LandrixXmlDecimalRound(Seconds, 9, xdrDown);
    if not LandrixXmlDecimalTryToInt64(LandrixXmlDecimalRound(S, 0, xdrDown), Whole) or (Whole = Low(Int64)) then
      Fail('FODT0002', 'the duration is too large');
  end;
  Result := DurationValueItem(Kind, M, S, DurationText(Kind, M, S));
end;

function ParseDuration(const Text: TLandrixXmlUtf8; Kind: TLandrixXmlXPathItemKind; Xp20: Boolean): TLandrixXmlXPathItem;
var
  S, Digits, Fraction: TLandrixXmlUtf8;
  I, Start, Order: Integer;
  Negative, InTime, TooLarge, Valid, YearMonth: Boolean;
  Value, Months, Whole: Int64;
  Seconds: TLandrixXmlDecimal;
begin
  S := Trimmed(Text);
  Valid := True;
  TooLarge := False;
  Negative := False;
  InTime := False;
  YearMonth := False;
  Months := 0;
  Whole := 0;
  Fraction := '';
  { 0 none yet, then 1 Y, 2 M, 3 D, 4 T, 5 H, 6 M, 7 S }
  Order := 0;
  I := 1;
  if (I <= Length(S)) and (S[I] = '-') then
  begin
    Negative := True;
    Inc(I);
  end;
  if (I > Length(S)) or (S[I] <> 'P') then
    Valid := False;
  Inc(I);
  if I > Length(S) then
    Valid := False;
  while Valid and (I <= Length(S)) do
  begin
    if S[I] = 'T' then
    begin
      Valid := not InTime and (I < Length(S));
      InTime := True;
      Order := 4;
      Inc(I);
      Continue;
    end;
    Start := I;
    while (I <= Length(S)) and (S[I] in ['0'..'9']) do
      Inc(I);
    Digits := Copy(S, Start, I - Start);
    if Digits = '' then
    begin
      Valid := False;
      Break;
    end;
    while (Length(Digits) > 1) and (Digits[1] = '0') do
      Delete(Digits, 1, 1);
    Value := 0;
    if Length(Digits) > 10 then
      TooLarge := True
    else
    begin
      Value := StrToInt64(LandrixXmlUtf8ToString(Digits));
      if Value > High(Integer) then
        TooLarge := True;
    end;
    if TooLarge then
      Value := 0;
    if (I <= Length(S)) and (S[I] = '.') then
    begin
      Inc(I);
      Start := I;
      while (I <= Length(S)) and (S[I] in ['0'..'9']) do
        Inc(I);
      Fraction := Copy(S, Start, I - Start);
      Valid := (Fraction <> '') and InTime and (I <= Length(S)) and (S[I] = 'S');
      if not Valid then
        Break;
    end;
    if I > Length(S) then
    begin
      Valid := False;
      Break;
    end;
    case S[I] of
      'Y':
        begin
          Valid := not InTime and (Order < 1);
          Order := 1;
          YearMonth := True;
          Months := Months + 12 * Value;
        end;
      'M':
        if InTime then
        begin
          Valid := Order < 6;
          Order := 6;
          Whole := Whole + 60 * Value;
        end
        else
        begin
          Valid := Order < 2;
          Order := 2;
          YearMonth := True;
          Months := Months + Value;
        end;
      'D':
        begin
          Valid := not InTime and (Order < 3);
          Order := 3;
          Whole := Whole + 86400 * Value;
        end;
      'H':
        begin
          Valid := InTime and (Order < 5);
          Order := 5;
          Whole := Whole + 3600 * Value;
        end;
      'S':
        begin
          Valid := InTime and (Order < 7);
          Order := 7;
          Whole := Whole + Value;
        end;
    else
      Valid := False;
    end;
    Inc(I);
  end;
  if Valid and (Kind = xikYearMonthDuration) then
    Valid := Order in [1, 2]
  else if Valid and (Kind = xikDayTimeDuration) then
    Valid := Order >= 3;
  if Valid and (Kind = xikDayTimeDuration) then
    Valid := not YearMonth;
  if not Valid then
    Fail('FORG0001', 'cannot convert ''' + LandrixXmlEscapeForMessage(Text, 60) + ''' to ' +
      LandrixXmlXPathAtomicTypeName(Kind));
  if TooLarge or (Length(Fraction) > 10) then
    Fail('FODT0002', 'the duration ''' + LandrixXmlEscapeForMessage(Text, 60) + ''' is too large');
  { Saxon reports FORG0001 }
  if (Months > High(Integer)) and Xp20 then
    Fail('FODT0002', 'the duration ''' + LandrixXmlEscapeForMessage(Text, 60) + ''' has too many months')
  else if Months > High(Integer) then
    Fail('FORG0001', 'the duration ''' + LandrixXmlEscapeForMessage(Text, 60) + ''' has too many months');
  Seconds := LandrixXmlDecimalFromInt64(Whole);
  if Fraction <> '' then
    Seconds := LandrixXmlDecimalAdd(Seconds, LandrixXmlDecimalMultiplyPow10(
      LandrixXmlParseDecimal(Copy(Fraction, 1, 9)), -Integer(Length(Copy(Fraction, 1, 9)))));
  if Negative then
  begin
    Months := -Months;
    Seconds := LandrixXmlDecimalNegate(Seconds);
  end;
  Result := DurationItem(Kind, LandrixXmlDecimalFromInt64(Months), Seconds);
end;

{ The order of two durations for Op: eq and ne on any durations, the
  others on two xs:yearMonthDuration or two xs:dayTimeDuration values. }
function CompareDurations(const A, B: TLandrixXmlXPathItem; Op: TLandrixXmlXPathCompare): Integer;
begin
  if Op in [xpcEq, xpcNe] then
  begin
    if (ItemMonths(A) = ItemMonths(B)) and (LandrixXmlDecimalCompare(ItemSeconds(A), ItemSeconds(B)) = 0) then
      Result := 0
    else
      Result := 1;
  end
  else if (A.Kind = xikYearMonthDuration) and (B.Kind = xikYearMonthDuration) then
  begin
    if ItemMonths(A) < ItemMonths(B) then
      Result := -1
    else if ItemMonths(A) > ItemMonths(B) then
      Result := 1
    else
      Result := 0;
  end
  else if (A.Kind = xikDayTimeDuration) and (B.Kind = xikDayTimeDuration) then
    Result := LandrixXmlDecimalCompare(ItemSeconds(A), ItemSeconds(B))
  else
  begin
    Fail('XPTY0004', 'cannot compare ' + KindName(A.Kind) + ' with ' + KindName(B.Kind) + ' by order');
    Result := 0;
  end;
end;

function CastTo(const Item: TLandrixXmlXPathItem; T: TLandrixXmlXPathItemKind;
  Xp20: Boolean): TLandrixXmlXPathItem; forward;
function DoubleToInteger(const D: TLandrixXmlDouble; Xp20: Boolean): TLandrixXmlDecimal; forward;

{ Compares two atomic values of comparable types (after the conversions of
  general or value comparisons). }
function CompareAtomic(const A, B: TLandrixXmlXPathItem; Op: TLandrixXmlXPathCompare): Boolean;
var
  Order: Integer;
begin
  if IsNumeric(A.Kind) and IsNumeric(B.Kind) then
    Order := CompareNumbers(A, B)
  else if IsStringLike(A.Kind) and IsStringLike(B.Kind) then
    Order := CompareStrings(A.Text, B.Text)
  else if (A.Kind = xikBoolean) and (B.Kind = xikBoolean) then
    Order := Ord(ItemBoolean(A)) - Ord(ItemBoolean(B))
  else if (A.Kind in [xikDate, xikDateTime, xikTime]) and (A.Kind = B.Kind) then
    Order := CompareDates(A, B)
  else if (A.Kind in DurationKinds) and (B.Kind in DurationKinds) then
    Order := CompareDurations(A, B, Op)
  else
  begin
    Fail('XPTY0004', 'cannot compare ' + KindName(A.Kind) + ' with ' + KindName(B.Kind));
    Order := 0;
  end;
  Result := Holds(Order, Op);
end;

{ "eq", "lt", ...: untypedAtomic is compared as a string. }
function ValueCompare(const A, B: TLandrixXmlXPathItem; Op: TLandrixXmlXPathCompare): Boolean;
begin
  Result := CompareAtomic(A, B, Op);
end;

{ The conversions of a general comparison for one pair. }
function ComparePair(const A, B: TLandrixXmlXPathItem; Op: TLandrixXmlXPathCompare; Xp20: Boolean): Boolean;
var
  X, Y: TLandrixXmlXPathItem;
begin
  X := A;
  Y := B;
  if X.Kind = xikUntypedAtomic then
  begin
    if IsNumeric(Y.Kind) then
      X := DoubleItem(ParseDouble(X.Text, Xp20))
    else if not IsStringLike(Y.Kind) then
      case Y.Kind of
        xikBoolean: X := CastTo(X, xikBoolean, Xp20);
        xikDate: X := CastTo(X, xikDate, Xp20);
        xikDateTime: X := CastTo(X, xikDateTime, Xp20);
        xikTime: X := CastTo(X, xikTime, Xp20);
        xikDuration, xikYearMonthDuration, xikDayTimeDuration: X := CastTo(X, Y.Kind, Xp20);
      else
        { compared as they are: a type error }
      end;
  end;
  if Y.Kind = xikUntypedAtomic then
  begin
    if IsNumeric(X.Kind) then
      Y := DoubleItem(ParseDouble(Y.Text, Xp20))
    else if not IsStringLike(X.Kind) then
      case X.Kind of
        xikBoolean: Y := CastTo(Y, xikBoolean, Xp20);
        xikDate: Y := CastTo(Y, xikDate, Xp20);
        xikDateTime: Y := CastTo(Y, xikDateTime, Xp20);
        xikTime: Y := CastTo(Y, xikTime, Xp20);
        xikDuration, xikYearMonthDuration, xikDayTimeDuration: Y := CastTo(Y, X.Kind, Xp20);
      else
        { compared as they are: a type error }
      end;
  end;
  Result := CompareAtomic(X, Y, Op);
end;

function GeneralCompare(const A, B: TLandrixXmlXPathSequence; Op: TLandrixXmlXPathCompare;
  Xp20: Boolean): Boolean;
var
  I, J: Integer;
begin
  for I := 0 to A.Count - 1 do
    for J := 0 to B.Count - 1 do
      if ComparePair(A.Items[I], B.Items[J], Op, Xp20) then
      begin
        Result := True;
        Exit;
      end;
  Result := False;
end;

{ Arithmetic operands: untypedAtomic becomes xs:double. }
function NumericOperand(const Item: TLandrixXmlXPathItem; Xp20: Boolean): TLandrixXmlXPathItem;
begin
  if Item.Kind = xikUntypedAtomic then
    Result := DoubleItem(ParseDouble(Item.Text, Xp20))
  else if IsNumeric(Item.Kind) then
  begin
    { the operators of the types derived from xs:integer are xs:integer's }
    Result := Item;
    Result.Kind := BasicKind(Item.Kind);
  end
  else
  begin
    if Item.Kind in [xikDate, xikDateTime, xikTime] then
      Fail('FOER0000', 'arithmetic on ' + KindName(Item.Kind) + ' is not supported');
    Fail('XPTY0004', 'arithmetic on ' + KindName(Item.Kind));
    Result := Item;
  end;
end;

{ The decimal value of the shortest digits of a finite double (Java's
  BigDecimal.valueOf). }
function ShortestDecimal(const D: TLandrixXmlDouble): TLandrixXmlDecimal;
var
  S: TLandrixXmlUtf8;
  I: Integer;
begin
  S := LandrixXmlDoubleFormat(D);
  I := Pos('E', LandrixXmlUtf8ToString(S));
  if I = 0 then
    Result := LandrixXmlParseDecimal(S)
  else
    Result := LandrixXmlDecimalMultiplyPow10(LandrixXmlParseDecimal(Copy(S, 1, I - 1)),
      StrToInt(LandrixXmlUtf8ToString(Copy(S, I + 1, MaxInt))));
end;

{ A duration times a number, or divided by one (Divide): the months
  rounded as fn:round, the seconds truncated to nanoseconds. An
  xs:double counts as the decimal of its shortest digits, and the
  product or quotient is exact. Saxon divides through xs:double: the
  months as a double quotient, the seconds times 1 div the number; it
  multiplies months by an xs:double as a double too. }
function ScaleDuration(const D, Number: TLandrixXmlXPathItem; Divide, Xp20: Boolean): TLandrixXmlXPathItem;
var
  N: TLandrixXmlXPathItem;
  Factor: TLandrixXmlDecimal;
  F, P: TLandrixXmlDouble;
begin
  N := NumericOperand(Number, Xp20);
  if not Xp20 and (Divide or ((N.Kind = xikDouble) and (D.Kind = xikYearMonthDuration))) then
  begin
    F := ToDouble(N);
    if LandrixXmlDoubleIsNaN(F) then
      Fail('FOCA0005', 'NaN as the factor or divisor of a duration');
    if Divide and LandrixXmlDoubleIsZero(F) then
      Fail('FODT0002', 'division of a duration by zero');
    if D.Kind = xikYearMonthDuration then
    begin
      if Divide then
        P := LandrixXmlDoubleDivide(LandrixXmlDoubleFromInt64(ItemMonths(D)), F)
      else
        P := LandrixXmlDoubleMultiply(LandrixXmlDoubleFromInt64(ItemMonths(D)), F);
      if LandrixXmlDoubleIsNaN(P) or LandrixXmlDoubleIsInfinite(P) then
        Fail('FODT0002', 'the duration is too large');
      Result := DurationItem(D.Kind, LandrixXmlDoubleToDecimal(LandrixXmlDoubleRound(P, 0, xdrHalfCeiling)),
        LandrixXmlDecimalZero);
      Exit;
    end;
    N := DoubleItem(LandrixXmlDoubleDivide(LandrixXmlDoubleFromInt64(1), F));
    Divide := False;
  end;
  if N.Kind = xikDouble then
  begin
    if LandrixXmlDoubleIsNaN(ItemDouble(N)) then
      Fail('FOCA0005', 'NaN as the factor or divisor of a duration');
    if LandrixXmlDoubleIsInfinite(ItemDouble(N)) then
    begin
      if not Divide then
        Fail('FODT0002', 'the duration is too large');
      Result := DurationItem(D.Kind, LandrixXmlDecimalZero, LandrixXmlDecimalZero);
      Exit;
    end;
    Factor := ShortestDecimal(ItemDouble(N));
  end
  else
    Factor := ItemDecimal(N);
  if Divide and LandrixXmlDecimalIsZero(Factor) then
    Fail('FODT0002', 'division of a duration by zero');
  if D.Kind = xikYearMonthDuration then
  begin
    if Divide then
      Result := DurationItem(D.Kind, DivideRounded(LandrixXmlDecimalFromInt64(ItemMonths(D)), Factor, 0,
        xdrHalfCeiling), LandrixXmlDecimalZero)
    else
      Result := DurationItem(D.Kind, LandrixXmlDecimalRound(LandrixXmlDecimalMultiply(
        LandrixXmlDecimalFromInt64(ItemMonths(D)), Factor), 0, xdrHalfCeiling), LandrixXmlDecimalZero);
  end
  else if Divide then
    Result := DurationItem(D.Kind, LandrixXmlDecimalZero, DivideRounded(ItemSeconds(D), Factor, 9, xdrDown))
  else
    Result := DurationItem(D.Kind, LandrixXmlDecimalZero,
      LandrixXmlDecimalRound(LandrixXmlDecimalMultiply(ItemSeconds(D), Factor), 9, xdrDown));
end;

{ Arithmetic with a duration operand: the sum and difference of two
  durations of the same subtype, their quotient (xs:decimal), a duration
  times or divided by a number. xs:duration itself has no operators. }
function DurationArithmetic(const A, B: TLandrixXmlXPathItem; Op: TLandrixXmlXPathArithmetic;
  Xp20: Boolean): TLandrixXmlXPathItem;
var
  YearMonth: Boolean;

  { the operators of F&O 2.0 10.6 on dates and times with durations }
  function DateOperator: Boolean;
  begin
    if (A.Kind in [xikDate, xikDateTime]) and (B.Kind in [xikYearMonthDuration, xikDayTimeDuration]) or
      (A.Kind = xikTime) and (B.Kind = xikDayTimeDuration) then
      Result := Op in [xpaAdd, xpaSubtract]
    else
      Result := (Op = xpaAdd) and ((A.Kind in [xikYearMonthDuration, xikDayTimeDuration]) and
        (B.Kind in [xikDate, xikDateTime]) or (A.Kind = xikDayTimeDuration) and (B.Kind = xikTime));
  end;

  procedure NotAllowed;
  begin
    if DateOperator then
      Fail('FOER0000', 'arithmetic on ' + KindName(A.Kind) + ' and ' + KindName(B.Kind) + ' is not supported');
    Fail('XPTY0004', 'no arithmetic operator for ' + KindName(A.Kind) + ' and ' + KindName(B.Kind));
  end;

begin
  InitItem(Result, xikDayTimeDuration);
  if (A.Kind in DurationKinds) and (B.Kind in DurationKinds) then
  begin
    if (A.Kind <> B.Kind) or (A.Kind = xikDuration) then
      NotAllowed;
    YearMonth := A.Kind = xikYearMonthDuration;
    case Op of
      xpaAdd:
        Result := DurationItem(A.Kind, LandrixXmlDecimalAdd(LandrixXmlDecimalFromInt64(ItemMonths(A)),
          LandrixXmlDecimalFromInt64(ItemMonths(B))), LandrixXmlDecimalAdd(ItemSeconds(A), ItemSeconds(B)));
      xpaSubtract:
        Result := DurationItem(A.Kind, LandrixXmlDecimalSubtract(LandrixXmlDecimalFromInt64(ItemMonths(A)),
          LandrixXmlDecimalFromInt64(ItemMonths(B))), LandrixXmlDecimalSubtract(ItemSeconds(A), ItemSeconds(B)));
      xpaDivide:
        if YearMonth then
        begin
          if ItemMonths(B) = 0 then
            Fail('FOAR0001', 'division by a zero duration');
          Result := DecimalItem(DivideRounded(LandrixXmlDecimalFromInt64(ItemMonths(A)),
            LandrixXmlDecimalFromInt64(ItemMonths(B)), 20, xdrHalfEven));
        end
        else
        begin
          if LandrixXmlDecimalIsZero(ItemSeconds(B)) then
            Fail('FOAR0001', 'division by a zero duration');
          Result := DecimalItem(DivideRounded(ItemSeconds(A), ItemSeconds(B), 20, xdrHalfEven));
        end;
    else
      NotAllowed;
    end;
  end
  else if A.Kind in DurationKinds then
  begin
    if (A.Kind = xikDuration) or not (Op in [xpaMultiply, xpaDivide]) or
      not (IsNumeric(B.Kind) or (B.Kind = xikUntypedAtomic)) then
      NotAllowed;
    Result := ScaleDuration(A, B, Op = xpaDivide, Xp20);
  end
  else
  begin
    if (B.Kind = xikDuration) or (Op <> xpaMultiply) or not (IsNumeric(A.Kind) or (A.Kind = xikUntypedAtomic)) then
      NotAllowed;
    Result := ScaleDuration(B, A, False, Xp20);
  end;
end;

function DecimalScaleOf(const Item: TLandrixXmlXPathItem): Integer;
begin
  if BasicKind(Item.Kind) = xikInteger then
    Result := 0
  else
    Result := LandrixXmlDecimalScale(ItemDecimal(Item));
end;

function Arithmetic(const A0, B0: TLandrixXmlXPathItem; Op: TLandrixXmlXPathArithmetic;
  Xp20: Boolean): TLandrixXmlXPathItem;
var
  A, B: TLandrixXmlXPathItem;
  DA, DB, Q: TLandrixXmlDouble;
  IsInt: Boolean;
begin
  if (A0.Kind in DurationKinds) or (B0.Kind in DurationKinds) then
  begin
    Result := DurationArithmetic(A0, B0, Op, Xp20);
    Exit;
  end;
  A := NumericOperand(A0, Xp20);
  B := NumericOperand(B0, Xp20);
  if (A.Kind = xikDouble) or (B.Kind = xikDouble) then
  begin
    DA := ToDouble(A);
    DB := ToDouble(B);
    case Op of
      xpaAdd: Result := DoubleItem(LandrixXmlDoubleAdd(DA, DB));
      xpaSubtract: Result := DoubleItem(LandrixXmlDoubleSubtract(DA, DB));
      xpaMultiply: Result := DoubleItem(LandrixXmlDoubleMultiply(DA, DB));
      xpaDivide: Result := DoubleItem(LandrixXmlDoubleDivide(DA, DB));
      xpaModulo: Result := DoubleItem(LandrixXmlDoubleModulo(DA, DB));
    else
      begin
        if LandrixXmlDoubleIsZero(DB) then
          Fail('FOAR0001', 'integer division by zero');
        Q := LandrixXmlDoubleDivide(DA, DB);
        if LandrixXmlDoubleIsNaN(DA) or LandrixXmlDoubleIsNaN(DB) or LandrixXmlDoubleIsInfinite(DA) then
          Fail('FOAR0002', 'idiv of NaN or infinity');
        if LandrixXmlDoubleIsNaN(Q) or LandrixXmlDoubleIsInfinite(Q) then
          Fail('FOCA0002', 'the quotient of idiv is too large');
        Result := IntegerItem(DoubleToInteger(Q, Xp20));
      end;
    end;
    Exit;
  end;
  if (Op in [xpaDivide, xpaIntegerDivide, xpaModulo]) and LandrixXmlDecimalIsZero(ItemDecimal(B)) then
    Fail('FOAR0001', 'division by zero');
  if (A.Kind = xikInteger) and (B.Kind = xikInteger) then
  begin
    case Op of
      xpaAdd: Result := IntegerItem(LandrixXmlDecimalAdd(ItemDecimal(A), ItemDecimal(B)));
      xpaSubtract: Result := IntegerItem(LandrixXmlDecimalSubtract(ItemDecimal(A), ItemDecimal(B)));
      xpaMultiply: Result := IntegerItem(LandrixXmlDecimalMultiply(ItemDecimal(A), ItemDecimal(B)));
      xpaDivide:
        begin
          Result := DecimalItem(LandrixXmlDecimalDivideIntegers(ItemDecimal(A), ItemDecimal(B), IsInt));
          if IsInt then
            Result := IntegerItem(ItemDecimal(Result));
        end;
      xpaIntegerDivide: Result := IntegerItem(LandrixXmlDecimalIntegerQuotient(ItemDecimal(A), ItemDecimal(B)));
    else
      Result := IntegerItem(LandrixXmlDecimalModulo(ItemDecimal(A), ItemDecimal(B)));
    end;
    Exit;
  end;
  case Op of
    xpaAdd: Result := DecimalItem(LandrixXmlDecimalAdd(ItemDecimal(A), ItemDecimal(B)));
    xpaSubtract: Result := DecimalItem(LandrixXmlDecimalSubtract(ItemDecimal(A), ItemDecimal(B)));
    xpaMultiply: Result := DecimalItem(LandrixXmlDecimalMultiply(ItemDecimal(A), ItemDecimal(B)));
    xpaDivide:
      Result := DecimalItem(LandrixXmlDecimalDivideScaled(ItemDecimal(A), ItemDecimal(B), DecimalScaleOf(A),
        DecimalScaleOf(B)));
    xpaIntegerDivide: Result := IntegerItem(LandrixXmlDecimalIntegerQuotient(ItemDecimal(A), ItemDecimal(B)));
  else
    Result := DecimalItem(LandrixXmlDecimalModulo(ItemDecimal(A), ItemDecimal(B)));
  end;
end;

function UnaryOp(const Item: TLandrixXmlXPathItem; Negate, Xp20: Boolean): TLandrixXmlXPathItem;
begin
  Result := NumericOperand(Item, Xp20);
  if not Negate then
    Exit;
  if Result.Kind = xikDouble then
    Result := DoubleItem(LandrixXmlDoubleNegate(ItemDouble(Result)))
  else
    Result := DecimalKindItem(Result.Kind, LandrixXmlDecimalNegate(ItemDecimal(Result)));
end;

function RangeOf(const A, B: TLandrixXmlXPathSequence; Xp20: Boolean): TLandrixXmlXPathSequence;
var
  X, Y: TLandrixXmlXPathItem;
  Lo, Hi: Int64;
  I, Count: Integer;
begin
  Result := LandrixXmlXPathEmpty;
  if (A.Count = 0) or (B.Count = 0) then
    Exit;
  if (A.Count > 1) or (B.Count > 1) then
    Fail('XPTY0004', '"to" needs single items');
  X := A.Items[0];
  Y := B.Items[0];
  if X.Kind = xikUntypedAtomic then
    X := CastTo(X, xikInteger, Xp20);
  if Y.Kind = xikUntypedAtomic then
    Y := CastTo(Y, xikInteger, Xp20);
  if (BasicKind(X.Kind) <> xikInteger) or (BasicKind(Y.Kind) <> xikInteger) then
    Fail('XPTY0004', 'the operands of "to" must be integers');
  if LandrixXmlDecimalCompare(ItemDecimal(X), ItemDecimal(Y)) > 0 then
    Exit;
  if LandrixXmlDecimalCompare(LandrixXmlDecimalSubtract(ItemDecimal(Y), ItemDecimal(X)),
    LandrixXmlDecimalFromInt64(10000000)) >= 0 then
    Fail('FOAR0002', 'a range of more than 10000000 integers is not supported');
  if not LandrixXmlDecimalTryToInt64(ItemDecimal(X), Lo) or not LandrixXmlDecimalTryToInt64(ItemDecimal(Y), Hi) then
    Fail('FOAR0002', 'range bounds out of range');
  { at most 10000000 items, checked above }
  Count := Integer(Hi - Lo);
  for I := 0 to Count do
    LandrixXmlXPathAppend(Result, IntegerItemOf(Lo + I));
end;

{ Saxon converts a double below 2^63 with Java's (long) cast (the exact
  value truncated, 2^63 saturates to 2^63 - 1), larger ones through the
  shortest digits. }
function DoubleToIntegerAsSaxon(const D: TLandrixXmlDouble): TLandrixXmlDecimal;
var
  Limit, Exact: TLandrixXmlDecimal;
begin
  Limit := LandrixXmlDecimalAdd(LandrixXmlDecimalFromInt64(High(Int64)), LandrixXmlDecimalFromInt64(1));
  Exact := LandrixXmlDoubleToDecimal(D);
  if LandrixXmlDecimalCompare(LandrixXmlDecimalAbs(Exact), Limit) <= 0 then
  begin
    Result := LandrixXmlDecimalRound(Exact, 0, xdrDown);
    if LandrixXmlDecimalCompare(Result, Limit) >= 0 then
      Result := LandrixXmlDecimalFromInt64(High(Int64));
  end
  else
    Result := LandrixXmlDoubleToInteger(D);
end;

{ A double as xs:integer: XPath 2.0 truncates the exact value. }
function DoubleToInteger(const D: TLandrixXmlDouble; Xp20: Boolean): TLandrixXmlDecimal;
begin
  if Xp20 then
    Result := LandrixXmlDecimalRound(LandrixXmlDoubleToDecimal(D), 0, xdrDown)
  else
    Result := DoubleToIntegerAsSaxon(D);
end;

{ An xs:anyURI as XML Schema 1.0 allows it: every "%" starts an escape of
  two hexadecimal digits, and a ":" before the first "/", "?" or "#" ends
  a scheme (a letter, then letters, digits, "+", "-" and "."). }
function AnyUriValid(const S: TLandrixXmlUtf8): Boolean;
var
  I, Colon: Integer;
begin
  Result := False;
  Colon := 0;
  for I := 1 to Length(S) do
    if S[I] in ['/', '?', '#'] then
      Break
    else if S[I] = ':' then
    begin
      Colon := I;
      Break;
    end;
  if Colon > 0 then
  begin
    if (Colon = 1) or not (S[1] in ['A'..'Z', 'a'..'z']) then
      Exit;
    for I := 2 to Colon - 1 do
      if not (S[I] in ['A'..'Z', 'a'..'z', '0'..'9', '+', '-', '.']) then
        Exit;
  end;
  I := 1;
  while I <= Length(S) do
  begin
    if S[I] = '%' then
    begin
      if (I + 2 > Length(S)) or not (S[I + 1] in ['0'..'9', 'A'..'F', 'a'..'f']) or
        not (S[I + 2] in ['0'..'9', 'A'..'F', 'a'..'f']) then
        Exit;
      Inc(I, 2);
    end;
    Inc(I);
  end;
  Result := True;
end;

function BooleanFromText(const S: TLandrixXmlUtf8): TLandrixXmlXPathItem;
var
  T: TLandrixXmlUtf8;
begin
  T := Trimmed(S);
  if (T = 'true') or (T = '1') then
    Result := BooleanItem(True)
  else if (T = 'false') or (T = '0') then
    Result := BooleanItem(False)
  else
  begin
    Fail('FORG0001', 'cannot convert ''' + LandrixXmlEscapeForMessage(S, 60) + ''' to xs:boolean');
    Result := BooleanItem(False);
  end;
end;

{ True if the integer V is in the value space of the type T derived from
  xs:integer. }
function InIntegerRange(const V: TLandrixXmlDecimal; T: TLandrixXmlXPathItemKind): Boolean;

  function AtLeast(const Bound: TLandrixXmlUtf8): Boolean;
  begin
    Result := LandrixXmlDecimalCompare(V, LandrixXmlParseDecimal(Bound)) >= 0;
  end;

  function AtMost(const Bound: TLandrixXmlUtf8): Boolean;
  begin
    Result := LandrixXmlDecimalCompare(V, LandrixXmlParseDecimal(Bound)) <= 0;
  end;

begin
  case T of
    xikNonPositiveInteger: Result := AtMost('0');
    xikNegativeInteger: Result := AtMost('-1');
    xikLong: Result := AtLeast('-9223372036854775808') and AtMost('9223372036854775807');
    xikInt: Result := AtLeast('-2147483648') and AtMost('2147483647');
    xikShort: Result := AtLeast('-32768') and AtMost('32767');
    xikByte: Result := AtLeast('-128') and AtMost('127');
    xikNonNegativeInteger: Result := AtLeast('0');
    xikUnsignedLong: Result := AtLeast('0') and AtMost('18446744073709551615');
    xikUnsignedInt: Result := AtLeast('0') and AtMost('4294967295');
    xikUnsignedShort: Result := AtLeast('0') and AtMost('65535');
    xikUnsignedByte: Result := AtLeast('0') and AtMost('255');
    xikPositiveInteger: Result := AtLeast('1');
  else
    Result := True;
  end;
end;

{ True if the ASCII character C occurs in S (compared as bytes: no
  conversion, which could map other characters to C). }
function ContainsByte(const S: TLandrixXmlUtf8; C: AnsiChar): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to Integer(Length(S)) do
    if S[I] = C then
    begin
      Result := True;
      Exit;
    end;
end;

{ True if every character of S is an XML name character (fifth edition,
  as the reader); Name: the first one may start a name. }
function NameCharacters(const S: TLandrixXmlUtf8; Name: Boolean): Boolean;
var
  P, N: Integer;
  CP: Cardinal;
begin
  Result := S <> '';
  P := 1;
  while Result and (P <= Integer(Length(S))) do
  begin
    N := LandrixXmlDecodeUtf8(PAnsiChar(@S[P]), Integer(Length(S)) - P + 1, CP);
    if N = 0 then
      Result := False
    else if Name and (P = 1) then
      Result := LandrixXmlIsNameStartChar(CP)
    else
      Result := LandrixXmlIsNameChar(CP);
    Inc(P, N);
  end;
end;

{ xs:language: 1 to 8 letters, then any number of "-" and 1 to 8 letters
  or digits }
function IsLanguage(const S: TLandrixXmlUtf8): Boolean;
var
  I, Run: Integer;
  First: Boolean;
begin
  Result := S <> '';
  Run := 0;
  First := True;
  I := 1;
  while Result and (I <= Length(S)) do
  begin
    if S[I] = '-' then
    begin
      Result := Run > 0;
      Run := 0;
      First := False;
    end
    else
    begin
      Inc(Run);
      Result := (Run <= 8) and ((S[I] in ['a'..'z', 'A'..'Z']) or
        (not First and (S[I] in ['0'..'9'])));
    end;
    Inc(I);
  end;
  Result := Result and (Run > 0);
end;

{ The value of a type derived from xs:string: S with the white space of
  the type (normalizedString replaces TAB, CR and LF by spaces, the
  others also collapse spaces) if it is in the lexical space. }
function DerivedStringValue(var S: TLandrixXmlUtf8; T: TLandrixXmlXPathItemKind): Boolean;
var
  I: Integer;
begin
  if T = xikNormalizedString then
  begin
    for I := 1 to Length(S) do
      if S[I] in [#9, #10, #13] then
        S[I] := ' ';
    Result := True;
    Exit;
  end;
  S := NormalizeSpace(S);
  case T of
    xikToken: Result := True;
    xikLanguage: Result := IsLanguage(S);
    xikNMTOKEN: Result := NameCharacters(S, False);
    xikName: Result := NameCharacters(S, True);
  else
    { NCName, ID, IDREF, ENTITY }
    Result := NameCharacters(S, True) and (not ContainsByte(S, ':'));
  end;
end;

function CastTo(const Item: TLandrixXmlXPathItem; T: TLandrixXmlXPathItemKind;
  Xp20: Boolean): TLandrixXmlXPathItem;
var
  D: TLandrixXmlDecimal;
  Str: TLandrixXmlUtf8;
  F: TLandrixXmlDouble;
  StringSource: Boolean;

  procedure NotAllowed;
  begin
    Fail('XPTY0004', 'cannot cast ' + KindName(Item.Kind) + ' to ' + LandrixXmlXPathAtomicTypeName(T));
  end;

begin
  { xs:anyURI casts only to strings (and anyURI) }
  StringSource := BasicKind(Item.Kind) in [xikString, xikUntypedAtomic];
  InitItem(Result, xikString);
  case T of
    xikString:
      Result := StringItem(xikString, AtomicString(Item));
    xikUntypedAtomic, xikAnyAtomic:
      if T = xikAnyAtomic then
        Result := Item
      else
        Result := StringItem(xikUntypedAtomic, AtomicString(Item));
    xikAnyUri:
      if StringSource or (Item.Kind = xikAnyUri) then
      begin
        Result := StringItem(xikAnyUri, NormalizeSpace(Item.Text));
        { an xs:anyURI stays as it is (a cast to its own type) }
        if Xp20 and StringSource and not AnyUriValid(Result.Text) then
          Fail('FORG0001', 'invalid xs:anyURI ''' + LandrixXmlEscapeForMessage(Item.Text, 60) + '''');
      end
      else
        NotAllowed;
    xikBoolean:
      case BasicKind(Item.Kind) of
        xikBoolean:
          Result := Item;
        xikInteger, xikDecimal:
          Result := BooleanItem(not LandrixXmlDecimalIsZero(ItemDecimal(Item)));
        xikDouble:
          Result := BooleanItem(not LandrixXmlDoubleIsZero(ItemDouble(Item)) and
            not LandrixXmlDoubleIsNaN(ItemDouble(Item)));
      else
        if StringSource then
          Result := BooleanFromText(Item.Text)
        else
          NotAllowed;
      end;
    xikDecimal:
      case BasicKind(Item.Kind) of
        xikInteger, xikDecimal:
          Result := DecimalItem(ItemDecimal(Item));
        xikDouble:
          begin
            if LandrixXmlDoubleIsNaN(ItemDouble(Item)) or LandrixXmlDoubleIsInfinite(ItemDouble(Item)) then
              Fail('FOCA0002', 'cannot convert NaN or infinity to xs:decimal');
            Result := DecimalItem(LandrixXmlDoubleToDecimal(ItemDouble(Item)));
          end;
        xikBoolean:
          Result := DecimalItem(LandrixXmlDecimalFromInt64(Ord(ItemBoolean(Item))));
      else
        if StringSource then
        begin
          if not LandrixXmlTryParseDecimal(Item.Text, D) then
            Fail('FORG0001', 'cannot convert ''' + LandrixXmlEscapeForMessage(Item.Text, 60) + ''' to xs:decimal');
          Result := DecimalItem(D);
        end
        else
          NotAllowed;
      end;
    xikInteger:
      case BasicKind(Item.Kind) of
        xikInteger:
          begin
            Result := Item;
            Result.Kind := xikInteger;
          end;
        xikDecimal:
          Result := IntegerItem(LandrixXmlDecimalRound(ItemDecimal(Item), 0, xdrDown));
        xikDouble:
          begin
            if LandrixXmlDoubleIsNaN(ItemDouble(Item)) or LandrixXmlDoubleIsInfinite(ItemDouble(Item)) then
              Fail('FOCA0002', 'cannot convert NaN or infinity to xs:integer');
            Result := IntegerItem(DoubleToInteger(ItemDouble(Item), Xp20));
          end;
        xikBoolean:
          Result := IntegerItemOf(Ord(ItemBoolean(Item)));
      else
        if StringSource then
        begin
          if not LandrixXmlTryParseDecimalInteger(Item.Text, D) then
            Fail('FORG0001', 'cannot convert ''' + LandrixXmlEscapeForMessage(Item.Text, 60) + ''' to xs:integer');
          Result := IntegerItem(D);
        end
        else
          NotAllowed;
      end;
    xikDouble:
      case BasicKind(Item.Kind) of
        xikDouble:
          Result := Item;
        xikInteger, xikDecimal:
          Result := DoubleItem(LandrixXmlDoubleFromDecimal(ItemDecimal(Item)));
        xikBoolean:
          Result := DoubleItem(LandrixXmlDoubleFromInt64(Ord(ItemBoolean(Item))));
      else
        if StringSource then
        begin
          F := ParseDouble(Item.Text, Xp20);
          Result := DoubleItem(F);
        end
        else
          NotAllowed;
      end;
    xikDate, xikDateTime, xikTime:
      begin
        if StringSource then
        begin
          case T of
            xikDate: Result := ParseDateKind(Item.Text, xikDate);
            xikDateTime: Result := ParseDateKind(Item.Text, xikDateTime);
          else
            Result := ParseDateKind(Item.Text, xikTime);
          end;
        end
        else if (Item.Kind = xikDate) and (T = xikDate) or (Item.Kind = xikDateTime) and (T = xikDateTime) or
          (Item.Kind = xikTime) and (T = xikTime) then
          Result := Item
        else if Item.Kind in [xikDate, xikDateTime, xikTime] then
          Fail('FOER0000', 'casts between ' + KindName(Item.Kind) + ' and ' + LandrixXmlXPathAtomicTypeName(T) +
            ' are not supported')
        else
          NotAllowed;
      end;
    xikNonPositiveInteger .. xikPositiveInteger:
      begin
        { the messages name the target type }
        if not (StringSource or IsNumeric(Item.Kind) or (Item.Kind = xikBoolean)) then
          NotAllowed;
        if StringSource and not LandrixXmlTryParseDecimalInteger(Item.Text, D) then
          Fail('FORG0001', 'cannot convert ''' + LandrixXmlEscapeForMessage(Item.Text, 60) + ''' to ' +
            LandrixXmlXPathAtomicTypeName(T));
        Result := CastTo(Item, xikInteger, Xp20);
        if not InIntegerRange(ItemDecimal(Result), T) then
          Fail('FORG0001', LandrixXmlUtf8ToString(AtomicString(Result)) + ' is out of the range of ' +
            LandrixXmlXPathAtomicTypeName(T));
        Result.Kind := T;
      end;
    xikDuration, xikYearMonthDuration, xikDayTimeDuration:
      if StringSource then
        Result := ParseDuration(Item.Text, T, Xp20)
      else if Item.Kind in DurationKinds then
        Result := DurationItem(T, LandrixXmlDecimalFromInt64(ItemMonths(Item)), ItemSeconds(Item))
      else
        NotAllowed;
    xikNormalizedString .. xikENTITY:
      begin
        { through xs:string, then the white space and the lexical check }
        Str := AtomicString(CastTo(Item, xikString, Xp20));
        if not DerivedStringValue(Str, T) then
          Fail('FORG0001', 'cannot convert ''' + LandrixXmlEscapeForMessage(Str, 60) + ''' to ' +
            LandrixXmlXPathAtomicTypeName(T));
        Result := StringItem(T, Str);
      end;
  else
    Fail('FOER0000', 'casts to ' + LandrixXmlXPathAtomicTypeName(T) + ' are not supported');
  end;
end;

function Castable(const Item: TLandrixXmlXPathItem; T: TLandrixXmlXPathItemKind; Xp20: Boolean): Boolean;
begin
  try
    CastTo(Item, T, Xp20);
    Result := True;
  except
    on E: ELandrixXmlXPathError do
    begin
      if E.XPathCode = 'FOER0000' then
        raise;
      Result := False;
    end;
  end;
end;
