{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  XML Schema 1.0 simple types for the validation units: the built-in types,
  derivation by restriction with facets, and unions. A value is checked as
  the Xerces validator of the Java runtime (used by the KoSIT validator)
  checks it, and a failure reports the same "cvc-..." code: white space
  is normalized first, then the value is matched against the patterns of
  every type in the derivation chain (cvc-pattern-valid), then the
  lexical form of the primitive type is checked
  (cvc-datatype-valid.1.2.1), then the other facets in the fixed order of
  Xerces: maxLength, minLength, length, enumeration, fractionDigits,
  totalDigits, maxInclusive, maxExclusive, minInclusive, minExclusive,
  each as defined by the most derived type that has it.
  Text must be valid UTF-8, as values from the DOM always are; malformed
  UTF-8 raises ELandrixXmlError (xecInvalidUnicode) from name and pattern
  checks. An anyURI is only trimmed, not collapsed, unless a pattern
  facet applies, as in Xerces.

  Deliberate differences from the XML Schema specification, following
  Xerces: the length facets count UTF-16 code units (a character above
  U+FFFF counts twice), and Name, NCName, ID, IDREF and NMTOKEN use the
  character classes of XML 1.0 Fourth Edition. Seconds are compared as
  exact decimals, where Xerces uses doubles (only values with more than
  about 15 fraction digits differ).
  A union tries its member types in order (cvc-datatype-valid.1.2.3).

  Built-in types: anySimpleType, string, normalizedString, token,
  language, Name, NCName, ID, IDREF, NMTOKEN, boolean, decimal, integer and
  its twelve derived types, float, double, dateTime, time, date,
  gYearMonth, gYear, gMonthDay, gDay, gMonth, hexBinary, base64Binary,
  anyURI. Not supported (LandrixXmlXsdBuiltinType returns nil, the schema
  loader reports xecUnsupported): duration and its subtypes, QName,
  NOTATION, ENTITY, and the list types IDREFS, ENTITIES, NMTOKENS; also
  list types defined in schemas and facets on unions.

  Order of date and time values as in XML Schema 1.0, 3.2.7.4: a value
  without time zone lies somewhere between +14:00 and -14:00, so it is
  only ordered against a value with time zone if they are more than 14
  hours apart; otherwise a range facet fails. }

unit LandrixXmlXsdTypes;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  Contnrs,
  LandrixXmlBase,
  LandrixXmlDecimal,
  LandrixXmlDouble,
  LandrixXmlUnicode,
  LandrixXmlRegex;

const
  LandrixXmlXsdNamespace = 'http://www.w3.org/2001/XMLSchema';

type
  TLandrixXmlXsdWhiteSpace = (xwsPreserve, xwsReplace, xwsCollapse);

  TLandrixXmlXsdPrimitive = (
    xspAnySimpleType, xspString, xspBoolean, xspDecimal, xspFloat, xspDouble,
    xspDateTime, xspTime, xspDate, xspGYearMonth, xspGYear, xspGMonthDay, xspGDay, xspGMonth,
    xspHexBinary, xspBase64Binary, xspAnyURI
  );

  { Lexical rules of built-in types derived from string or decimal. }
  TLandrixXmlXsdLexicalRule = (xslNone, xslLanguage, xslName, xslNCName, xslNmToken, xslInteger);

  TLandrixXmlXsdFacet = (
    xsfLength, xsfMinLength, xsfMaxLength, xsfPattern, xsfEnumeration, xsfWhiteSpace,
    xsfMaxInclusive, xsfMaxExclusive, xsfMinInclusive, xsfMinExclusive,
    xsfTotalDigits, xsfFractionDigits
  );

  TLandrixXmlXsdVariety = (xsvAtomic, xsvUnion);

  { Date and time fields; unused fields are 0 (Year, Month, Day) or 0 for
    the time of a pure date. Second may have a fraction. }
  TLandrixXmlXsdDateTime = record
    Year: Integer;
    Month: Integer;
    Day: Integer;
    Hour: Integer;
    Minute: Integer;
    Second: TLandrixXmlDecimal;
    HasTimeZone: Boolean;
    TimeZone: Integer; { minutes east of UTC }
  end;

  TLandrixXmlXsdSimpleType = class;

  { A value in the value space of a primitive type. Text is the lexical
    form after white space normalization, RawText the value as given;
    Length is the length counted by the length facets (characters as
    UTF-16 code units like Xerces, or octets for the binary types).
    MemberType is the member type of a union that accepted the value, else
    the validated type itself. }
  TLandrixXmlXsdValue = record
    Primitive: TLandrixXmlXsdPrimitive;
    Text: TLandrixXmlUtf8;
    RawText: TLandrixXmlUtf8;
    MemberType: TLandrixXmlXsdSimpleType;
    Length: Integer;
    DecimalValue: TLandrixXmlDecimal;
    DoubleValue: TLandrixXmlDouble;
    BooleanValue: Boolean;
    DateTime: TLandrixXmlXsdDateTime;
  end;

  { A failed check: Code is the Xerces code ("cvc-pattern-valid"),
    Message an English text in the style of Xerces. }
  TLandrixXmlXsdError = record
    Code: string;
    Message: string;
  end;

  TLandrixXmlXsdSimpleTypeArray = array of TLandrixXmlXsdSimpleType;
  TLandrixXmlXsdValueArray = array of TLandrixXmlXsdValue;

  { A bound of a range facet. }
  TLandrixXmlXsdBound = record
    Present: Boolean;
    Value: TLandrixXmlXsdValue;
  end;

  TLandrixXmlXsdSimpleType = class
  private
    FNamespaceUri: TLandrixXmlUtf8;
    FName: TLandrixXmlUtf8;
    FAnonymousName: TLandrixXmlUtf8;
    FBase: TLandrixXmlXsdSimpleType;
    FVariety: TLandrixXmlXsdVariety;
    FPrimitive: TLandrixXmlXsdPrimitive;
    FLexicalRule: TLandrixXmlXsdLexicalRule;
    FWhiteSpace: TLandrixXmlXsdWhiteSpace;
    FMembers: TLandrixXmlXsdSimpleTypeArray;
    FBuiltin: Boolean;
    { own facets (not inherited) }
    FLength: Integer;
    FMinLength: Integer;
    FMaxLength: Integer;
    FPatterns: TObjectList;  { TLandrixXmlRegex, any one must match }
    FEnumeration: TLandrixXmlXsdValueArray;
    FEnumerationCount: Integer;
    FMinInclusive: TLandrixXmlXsdBound;
    FMaxInclusive: TLandrixXmlXsdBound;
    FMinExclusive: TLandrixXmlXsdBound;
    FMaxExclusive: TLandrixXmlXsdBound;
    FTotalDigits: Integer;
    FFractionDigits: Integer;
    procedure InitFacets;
    function CheckFacets(const Value: TLandrixXmlXsdValue; out Error: TLandrixXmlXsdError): Boolean;
    function ValidatorName: string;
    function HasPatterns: Boolean;
    function IsTrimmedType: Boolean;
    function CheckPatterns(const Value: TLandrixXmlXsdValue; const TypeName: string;
      out Error: TLandrixXmlXsdError): Boolean;
    function ParseFacetValue(const Text: TLandrixXmlUtf8): TLandrixXmlXsdValue;
  public
    { A built-in type; used by the unit itself. }
    constructor CreateBuiltin(const Name: TLandrixXmlUtf8; Base: TLandrixXmlXsdSimpleType;
      Primitive: TLandrixXmlXsdPrimitive; WhiteSpace: TLandrixXmlXsdWhiteSpace;
      LexicalRule: TLandrixXmlXsdLexicalRule);
    { A type derived from Base by restriction; Name is '' for an anonymous
      type. Facets are added afterwards. }
    constructor CreateRestriction(Base: TLandrixXmlXsdSimpleType; const NamespaceUri, Name: TLandrixXmlUtf8);
    { A union of Members (tried in this order). }
    constructor CreateUnion(const Members: array of TLandrixXmlXsdSimpleType;
      const NamespaceUri, Name: TLandrixXmlUtf8);
    destructor Destroy; override;
    { Adds a facet as written in the schema. Several patterns of the same
      type are alternatives. Raises ELandrixXmlError: xecInvalidArgument for
      a facet value that is invalid or not allowed for the base type,
      xecUnsupported for facets on a union. }
    procedure AddFacet(Facet: TLandrixXmlXsdFacet; const Value: TLandrixXmlUtf8);
    { Checks Text (an element or attribute value as written). }
    function Validate(const Text: TLandrixXmlUtf8; out Value: TLandrixXmlXsdValue;
      out Error: TLandrixXmlXsdError): Boolean;
    property NamespaceUri: TLandrixXmlUtf8 read FNamespaceUri;
    property Name: TLandrixXmlUtf8 read FName;
    { For an anonymous type: the name messages use, as the schema loader
      gives it (Xerces' #AnonType_ followed by the names of the enclosing
      declarations). }
    property AnonymousName: TLandrixXmlUtf8 read FAnonymousName write FAnonymousName;
    property Base: TLandrixXmlXsdSimpleType read FBase;
    property Variety: TLandrixXmlXsdVariety read FVariety;
    property Primitive: TLandrixXmlXsdPrimitive read FPrimitive;
    property LexicalRule: TLandrixXmlXsdLexicalRule read FLexicalRule;
    property WhiteSpace: TLandrixXmlXsdWhiteSpace read FWhiteSpace;
    property Builtin: Boolean read FBuiltin;
    { The name Xerces uses for the type in messages: the name, the
      AnonymousName, or #AnonType_ and the name of the nearest named base. }
    function DisplayName: string;
    { True if AType is this type or one of its base types (to recognize ID
      and IDREF values). }
    function IsDerivedFrom(AType: TLandrixXmlXsdSimpleType): Boolean;
  end;

{ The built-in type with this local name in the XML Schema namespace, or
  nil if it is unknown or not supported. The types are shared; never free
  them. }
function LandrixXmlXsdBuiltinType(const LocalName: TLandrixXmlUtf8): TLandrixXmlXsdSimpleType;

{ A value as Xerces prints it in messages, its canonical form: a decimal
  with ".0" unless its type is an integer type, a boolean as true or
  false, float and double as 1.5E3 (zero as 0.0E1), dates and times with
  a time zone moved to UTC ("2025-12-31Z"), hexBinary in upper case,
  base64Binary without white space, other values in their normalized
  lexical form. }
function LandrixXmlXsdValueText(const Value: TLandrixXmlXsdValue): TLandrixXmlUtf8;

{ A key for comparing values as Xerces does for identity constraints:
  equal keys for equal values (0 and -0, all NaNs, the same instant in
  different time zones), different keys for values of different
  primitive types (integer types count as decimal). }
function LandrixXmlXsdValueKey(const Value: TLandrixXmlXsdValue): TLandrixXmlUtf8;

{ -1, 0, 1, or LandrixXmlXsdIncomparable. }
function LandrixXmlXsdCompareValues(const A, B: TLandrixXmlXsdValue): Integer;

const
  LandrixXmlXsdIncomparable = 2;

{ White space processing of the whiteSpace facet. }
function LandrixXmlXsdNormalizeWhiteSpace(const S: TLandrixXmlUtf8;
  Mode: TLandrixXmlXsdWhiteSpace): TLandrixXmlUtf8;

implementation

{$I LandrixXmlNameData4.inc}

{ ---------------------------------------------------------------------- }
{ Helpers                                                                }
{ ---------------------------------------------------------------------- }

function IsXmlSpace(C: AnsiChar): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13);
end;

function LandrixXmlXsdNormalizeWhiteSpace(const S: TLandrixXmlUtf8;
  Mode: TLandrixXmlXsdWhiteSpace): TLandrixXmlUtf8;
var
  I, N: Integer;
  PendingSpace: Boolean;
begin
  if Mode = xwsPreserve then
  begin
    Result := S;
    Exit;
  end;
  Result := '';
  SetLength(Result, Length(S));
  N := 0;
  if Mode = xwsReplace then
  begin
    for I := 1 to Length(S) do
    begin
      Inc(N);
      if IsXmlSpace(AnsiChar(S[I])) then
        Result[N] := ' '
      else
        Result[N] := S[I];
    end;
  end
  else
  begin
    PendingSpace := False;
    for I := 1 to Length(S) do
      if IsXmlSpace(AnsiChar(S[I])) then
        PendingSpace := N > 0
      else
      begin
        if PendingSpace then
        begin
          Inc(N);
          Result[N] := ' ';
          PendingSpace := False;
        end;
        Inc(N);
        Result[N] := S[I];
      end;
  end;
  SetLength(Result, N);
end;

{ Values are quoted whole, as Xerces does. }
function Quote(const S: TLandrixXmlUtf8): string;
begin
  Result := '''' + LandrixXmlEscapeForMessage(S, MaxInt) + '''';
end;

procedure SetError(out Error: TLandrixXmlXsdError; const Code, Msg: string);
begin
  Error.Code := Code;
  Error.Message := Msg;
end;

function CharIn(C: AnsiChar; const Chars: AnsiString): Boolean;
var
  I: Integer;
begin
  for I := 1 to Length(Chars) do
    if Chars[I] = C then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

function IsDigit(C: AnsiChar): Boolean;
begin
  Result := (C >= '0') and (C <= '9');
end;

function IsAsciiLetter(C: AnsiChar): Boolean;
begin
  Result := ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z'));
end;

{ Length in UTF-16 code units, as Xerces counts the length facets
  (String.length in Java): a character above U+FFFF counts twice, unlike
  the code point count of the XML Schema specification. }
function Utf16Length(const S: TLandrixXmlUtf8): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) do
    if Ord(S[I]) >= $F0 then
      Inc(Result, 2)
    else if (Ord(S[I]) and $C0) <> $80 then
      Inc(Result);
end;

{ ---------------------------------------------------------------------- }
{ Lexical forms                                                          }
{ ---------------------------------------------------------------------- }

function DaysInMonth(Year, Month: Integer): Integer;
const
  Days: array[1..12] of Integer = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
begin
  Result := Days[Month];
  { the Gregorian rule on the signed year, as Xerces applies it (so -0004
    is a leap year, -0001 is not) }
  if (Month = 2) and (((Year mod 4 = 0) and (Year mod 100 <> 0)) or (Year mod 400 = 0)) then
    Result := 29;
end;

{ Reads exactly Count digits at P (1-based) into Value. }
function ReadDigits(const S: TLandrixXmlUtf8; var P: Integer; Count: Integer; out Value: Integer): Boolean;
var
  I: Integer;
begin
  Value := 0;
  Result := False;
  for I := 1 to Count do
  begin
    if (P > Length(S)) or not IsDigit(AnsiChar(S[P])) then
      Exit;
    Value := Value * 10 + (Ord(S[P]) - Ord('0'));
    Inc(P);
  end;
  Result := True;
end;

function Expect(const S: TLandrixXmlUtf8; var P: Integer; C: AnsiChar): Boolean;
begin
  Result := (P <= Length(S)) and (AnsiChar(S[P]) = C);
  if Result then
    Inc(P);
end;

{ -?YYYY+ without leading zeros beyond four digits; 0000 is invalid
  (XML Schema 1.0). }
function ReadYear(const S: TLandrixXmlUtf8; var P: Integer; out Year: Integer): Boolean;
var
  Negative: Boolean;
  First, Digits: Integer;
  Value: Int64;
begin
  Result := False;
  Year := 0;
  Negative := Expect(S, P, '-');
  First := P;
  Digits := 0;
  Value := 0;
  while (P <= Length(S)) and IsDigit(AnsiChar(S[P])) do
  begin
    { Xerces accepts years within the Java int range }
    if Digits >= 10 then
      Exit;
    Value := Value * 10 + (Int64(Ord(S[P])) - Ord('0'));
    Inc(Digits);
    Inc(P);
  end;
  if (Digits < 4) or ((Digits > 4) and (S[First] = '0')) or (Value = 0) then
    Exit;
  if Negative then
    Value := -Value;
  if (Value > High(Integer)) or (Value < Low(Integer)) then
    Exit;
  Year := Integer(Value);
  Result := True;
end;

function ReadTimeZone(const S: TLandrixXmlUtf8; var P: Integer;
  var Value: TLandrixXmlXsdDateTime): Boolean;
var
  Sign, H, M: Integer;
begin
  Result := True;
  Value.HasTimeZone := False;
  Value.TimeZone := 0;
  if P > Length(S) then
    Exit;
  Result := False;
  if S[P] = 'Z' then
  begin
    Inc(P);
    Value.HasTimeZone := True;
    Result := True;
    Exit;
  end;
  if S[P] = '+' then
    Sign := 1
  else if S[P] = '-' then
    Sign := -1
  else
    Exit;
  Inc(P);
  if not ReadDigits(S, P, 2, H) or not Expect(S, P, ':') or not ReadDigits(S, P, 2, M) then
    Exit;
  if (M > 59) or (H > 14) or ((H = 14) and (M > 0)) then
    Exit;
  Value.HasTimeZone := True;
  Value.TimeZone := Sign * (H * 60 + M);
  Result := True;
end;

{ hh:mm:ss(.s+)? ; 24:00:00 is allowed (XML Schema 1.0). }
function ReadTime(const S: TLandrixXmlUtf8; var P: Integer; var Value: TLandrixXmlXsdDateTime): Boolean;
var
  Sec, Start: Integer;
  Text: TLandrixXmlUtf8;
begin
  Result := False;
  if not ReadDigits(S, P, 2, Value.Hour) or not Expect(S, P, ':') or
    not ReadDigits(S, P, 2, Value.Minute) or not Expect(S, P, ':') then
    Exit;
  Start := P;
  if not ReadDigits(S, P, 2, Sec) then
    Exit;
  if (P <= Length(S)) and (S[P] = '.') then
  begin
    Inc(P);
    if (P > Length(S)) or not IsDigit(AnsiChar(S[P])) then
      Exit;
    while (P <= Length(S)) and IsDigit(AnsiChar(S[P])) do
      Inc(P);
  end;
  Text := Copy(S, Start, P - Start);
  Value.Second := LandrixXmlParseDecimal(Text);
  if (Value.Minute > 59) or (Sec > 59) then
    Exit;
  if Value.Hour = 24 then
  begin
    if (Value.Minute <> 0) or not LandrixXmlDecimalIsZero(Value.Second) then
      Exit;
  end
  else if Value.Hour > 23 then
    Exit;
  Result := True;
end;

function ParseDateTimeKind(const S: TLandrixXmlUtf8; Kind: TLandrixXmlXsdPrimitive;
  out Value: TLandrixXmlXsdDateTime): Boolean;
var
  P: Integer;
begin
  Result := False;
  Value.Year := 0;
  Value.Month := 0;
  Value.Day := 0;
  Value.Hour := 0;
  Value.Minute := 0;
  Value.Second := LandrixXmlDecimalZero;
  Value.HasTimeZone := False;
  Value.TimeZone := 0;
  P := 1;
  case Kind of
    xspDateTime, xspDate, xspGYearMonth, xspGYear:
      begin
        if not ReadYear(S, P, Value.Year) then
          Exit;
        if Kind <> xspGYear then
        begin
          if not Expect(S, P, '-') or not ReadDigits(S, P, 2, Value.Month) then
            Exit;
          if (Value.Month < 1) or (Value.Month > 12) then
            Exit;
        end;
        if Kind in [xspDateTime, xspDate] then
        begin
          if not Expect(S, P, '-') or not ReadDigits(S, P, 2, Value.Day) then
            Exit;
          if (Value.Day < 1) or (Value.Day > DaysInMonth(Value.Year, Value.Month)) then
            Exit;
        end;
        if Kind = xspDateTime then
          if not Expect(S, P, 'T') or not ReadTime(S, P, Value) then
            Exit;
      end;
    xspTime:
      if not ReadTime(S, P, Value) then
        Exit;
    xspGMonthDay, xspGDay, xspGMonth:
      begin
        if not Expect(S, P, '-') or not Expect(S, P, '-') then
          Exit;
        if Kind = xspGDay then
        begin
          if not Expect(S, P, '-') or not ReadDigits(S, P, 2, Value.Day) then
            Exit;
          if (Value.Day < 1) or (Value.Day > 31) then
            Exit;
        end
        else
        begin
          if not ReadDigits(S, P, 2, Value.Month) or (Value.Month < 1) or (Value.Month > 12) then
            Exit;
          { Xerces also accepts --MM--, the form of XML Schema 1.0 before
            its errata }
          if (Kind = xspGMonth) and (P + 1 <= Length(S)) and (S[P] = '-') and (S[P + 1] = '-') then
            Inc(P, 2);
          if Kind = xspGMonthDay then
          begin
            if not Expect(S, P, '-') or not ReadDigits(S, P, 2, Value.Day) then
              Exit;
            { 02-29 is a valid gMonthDay }
            if (Value.Day < 1) or (Value.Day > DaysInMonth(2000, Value.Month)) then
              Exit;
          end;
        end;
      end;
  else
    Exit;
  end;
  if not ReadTimeZone(S, P, Value) then
    Exit;
  Result := P > Length(S);
end;

function HexValue(C: AnsiChar): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

{ base64Binary (XML Schema 1.0 errata): groups of four characters of the
  alphabet, single spaces allowed between characters, padding only at the
  end with the restricted characters before it. Returns the octet count
  or -1. }
function Base64Length(const S: TLandrixXmlUtf8): Integer;
const
  Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
var
  Chars: AnsiString;
  I, N, Pads: Integer;
  C: AnsiChar;
  Last: AnsiChar;
begin
  Result := -1;
  Chars := '';
  SetLength(Chars, Length(S));
  N := 0;
  for I := 1 to Length(S) do
  begin
    C := AnsiChar(S[I]);
    if C = ' ' then
      Continue;
    if not CharIn(C, Alphabet) and (C <> '=') then
      Exit;
    Inc(N);
    Chars[N] := C;
  end;
  SetLength(Chars, N);
  if N mod 4 <> 0 then
    Exit;
  Pads := 0;
  while (Pads < N) and (Chars[N - Pads] = '=') do
    Inc(Pads);
  if Pads > 2 then
    Exit;
  for I := 1 to N - Pads do
    if Chars[I] = '=' then
      Exit;
  if Pads > 0 then
  begin
    Last := Chars[N - Pads];
    { the bits after the data must be zero }
    if (Pads = 2) and not CharIn(Last, 'AQgw') then
      Exit;
    if (Pads = 1) and not CharIn(Last, 'AEIMQUYcgkosw048') then
      Exit;
  end;
  Result := (N div 4) * 3 - Pads;
end;

function IsSchemeChar(C: AnsiChar; First: Boolean): Boolean;
begin
  Result := IsAsciiLetter(C) or (not First and (IsDigit(C) or (C = '+') or (C = '-') or (C = '.')));
end;

{ Groups of one to four hex digits separated by ':' (S[First..Last]); -1 if
  malformed, 0 for an empty range. }
function HexGroups(const S: TLandrixXmlUtf8; First, Last: Integer): Integer;
var
  I, Digits, Count: Integer;
begin
  Result := 0;
  if First > Last then
    Exit;
  Result := -1;
  Count := 0;
  Digits := 0;
  for I := First to Last do
    if S[I] = ':' then
    begin
      if Digits = 0 then
        Exit;
      Digits := 0;
    end
    else if HexValue(AnsiChar(S[I])) >= 0 then
    begin
      if Digits = 0 then
        Inc(Count);
      Inc(Digits);
      if Digits > 4 then
        Exit;
    end
    else
      Exit;
  if Digits > 0 then
    Result := Count;
end;

{ A dotted IPv4 address (S[First..Last]). }
function IsIPv4(const S: TLandrixXmlUtf8; First, Last: Integer): Boolean;
var
  I, Dots, Octet, Digits: Integer;
begin
  Result := False;
  Dots := 0;
  Octet := 0;
  Digits := 0;
  for I := First to Last do
    if S[I] = '.' then
    begin
      if Digits = 0 then
        Exit;
      Inc(Dots);
      Octet := 0;
      Digits := 0;
    end
    else if IsDigit(AnsiChar(S[I])) then
    begin
      Octet := Octet * 10 + (Ord(S[I]) - Ord('0'));
      Inc(Digits);
      if (Octet > 255) or (Digits > 3) then
        Exit;
    end
    else
      Exit;
  Result := (Dots = 3) and (Digits > 0);
end;

{ An IPv6 address between the brackets of a URI host: up to eight groups
  of one to four hex digits, at most one '::', optionally ending with a
  dotted IPv4 address that counts as two groups. }
function IsIPv6(const S: TLandrixXmlUtf8): Boolean;
var
  I, Last, Double, Left, Right, Extra, LastColon: Integer;
  HasDot: Boolean;
begin
  Result := False;
  Last := Length(S);
  Extra := 0;
  { a dotted IPv4 tail after the last colon }
  HasDot := False;
  for I := 1 to Last do
    if S[I] = '.' then
      HasDot := True;
  if HasDot then
  begin
    LastColon := 0;
    for I := Last downto 1 do
      if S[I] = ':' then
      begin
        LastColon := I;
        Break;
      end;
    if (LastColon = 0) or not IsIPv4(S, LastColon + 1, Last) then
      Exit;
    Extra := 2;
    { keep a '::' directly before the tail, drop a single ':' }
    if (LastColon > 1) and (S[LastColon - 1] = ':') then
      Last := LastColon
    else
      Last := LastColon - 1;
  end;
  Double := 0;
  for I := 1 to Last - 1 do
    if (S[I] = ':') and (S[I + 1] = ':') then
    begin
      if Double > 0 then
        Exit;
      Double := I;
    end;
  if Double = 0 then
  begin
    Left := HexGroups(S, 1, Last);
    Result := (Left >= 0) and (Left + Extra = 8);
  end
  else
  begin
    Left := HexGroups(S, 1, Double - 1);
    Right := HexGroups(S, Double + 2, Last);
    Result := (Left >= 0) and (Right >= 0) and (Left + Right + Extra <= 7);
  end;
end;

function HasBracket(const S: TLandrixXmlUtf8; First, Last: Integer): Boolean;
var
  I: Integer;
begin
  for I := First to Last do
    if (S[I] = '[') or (S[I] = ']') then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

{ The authority of a hierarchical URI (S[First..Last]): brackets only
  around an IPv6 host, after an optional "userinfo@" and before an
  optional ":port" of digits. }
function IsValidAuthority(const S: TLandrixXmlUtf8; First, Last: Integer): Boolean;
var
  Open, Close, I: Integer;
begin
  Result := True;
  if not HasBracket(S, First, Last) then
    Exit;
  Result := False;
  Open := 0;
  Close := 0;
  for I := First to Last do
    if (S[I] = '[') and (Open = 0) then
      Open := I
    else if (S[I] = ']') and (Close = 0) then
      Close := I;
  if (Open = 0) or (Close < Open) then
    Exit;
  { before '[': nothing, or a userinfo ending with its only '@' (Xerces
    takes the text up to the first '@' as userinfo) }
  if (Open > First) and (S[Open - 1] <> '@') then
    Exit;
  for I := First to Open - 2 do
    if S[I] = '@' then
      Exit;
  if HasBracket(S, First, Open - 1) then
    Exit;
  if not IsIPv6(Copy(S, Open + 1, Close - Open - 1)) then
    Exit;
  { after ']': nothing, or ':' and digits }
  if Close < Last then
  begin
    if S[Close + 1] <> ':' then
      Exit;
    for I := Close + 2 to Last do
      if not IsDigit(AnsiChar(S[I])) then
        Exit;
  end;
  Result := True;
end;

{ anyURI as the URI class of Xerces checks it (characters outside US-ASCII,
  spaces and the like are escaped by Xerces first and so always allowed):
  - a colon before the first '/', '?' or '#' ends a scheme, which must be
    valid and be followed by something other than '#' or nothing;
  - a hierarchical reference (no scheme, or the part after the scheme
    starts with '/') may contain '[' and ']' before its query and fragment
    only around an IPv6 host; "//" must be followed by something;
  - '%' must start an escape of two hex digits; there is at most one '#'. }
function IsValidUri(const S: TLandrixXmlUtf8): Boolean;
var
  I, Colon, Stop, Rest, PartEnd, AuthEnd: Integer;
  Hash: Boolean;
begin
  Result := False;
  { %-escapes and fragments anywhere }
  Hash := False;
  I := 1;
  while I <= Length(S) do
  begin
    if S[I] = '%' then
    begin
      if (I + 2 > Length(S)) or (HexValue(AnsiChar(S[I + 1])) < 0) or (HexValue(AnsiChar(S[I + 2])) < 0) then
        Exit;
      Inc(I, 3);
      Continue;
    end;
    if S[I] = '#' then
    begin
      if Hash then
        Exit;
      Hash := True;
    end;
    Inc(I);
  end;
  { scheme }
  Stop := Length(S) + 1;
  for I := 1 to Length(S) do
    if (S[I] = '/') or (S[I] = '?') or (S[I] = '#') then
    begin
      Stop := I;
      Break;
    end;
  Colon := 0;
  for I := 1 to Stop - 1 do
    if S[I] = ':' then
    begin
      Colon := I;
      Break;
    end;
  Rest := 1;
  if Colon > 0 then
  begin
    if Colon = 1 then
      Exit;
    for I := 1 to Colon - 1 do
      if not IsSchemeChar(AnsiChar(S[I]), I = 1) then
        Exit;
    Rest := Colon + 1;
    if (Rest > Length(S)) or (S[Rest] = '#') then
      Exit;
    { an opaque URI (mailto:x, urn:a[1]) has no further rules }
    if S[Rest] <> '/' then
    begin
      Result := True;
      Exit;
    end;
  end;
  { hierarchical: the part before query and fragment }
  PartEnd := Length(S);
  for I := Rest to Length(S) do
    if (S[I] = '?') or (S[I] = '#') then
    begin
      PartEnd := I - 1;
      Break;
    end;
  if (Rest + 1 <= Length(S)) and (S[Rest] = '/') and (S[Rest + 1] = '/') then
  begin
    { "//" alone or "scheme://" at the end is incomplete }
    if Rest + 2 > Length(S) then
      Exit;
    AuthEnd := PartEnd;
    for I := Rest + 2 to PartEnd do
      if S[I] = '/' then
      begin
        AuthEnd := I - 1;
        Break;
      end;
    if not IsValidAuthority(S, Rest + 2, AuthEnd) then
      Exit;
    if HasBracket(S, AuthEnd + 1, PartEnd) then
      Exit;
  end
  else if HasBracket(S, Rest, PartEnd) then
    Exit;
  Result := True;
end;

function IsLanguage(const S: TLandrixXmlUtf8): Boolean;
var
  I, Part: Integer;
  First: Boolean;
begin
  Result := False;
  Part := 0;
  First := True;
  for I := 1 to Length(S) do
  begin
    if S[I] = '-' then
    begin
      if Part = 0 then
        Exit;
      Part := 0;
      First := False;
    end
    else if IsAsciiLetter(AnsiChar(S[I])) or (not First and IsDigit(AnsiChar(S[I]))) then
    begin
      Inc(Part);
      if Part > 8 then
        Exit;
    end
    else
      Exit;
  end;
  Result := Part > 0;
end;

function InRanges(const Ranges: array of Integer; CodePoint: Integer): Boolean;
var
  Lo, Hi, Mid: Integer;
begin
  Lo := 0;
  Hi := Integer(Length(Ranges)) div 2 - 1;
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if CodePoint < Ranges[2 * Mid] then
      Hi := Mid - 1
    else if CodePoint > Ranges[2 * Mid + 1] then
      Lo := Mid + 1
    else
    begin
      Result := True;
      Exit;
    end;
  end;
  Result := False;
end;

{ Name, NCName (no colon) or NMTOKEN (only name characters), with the
  character classes of XML 1.0 Fourth Edition as Xerces checks them (the
  parser uses the Fifth Edition, which allows more characters). }
function IsNameKind(const S: TLandrixXmlUtf8; Rule: TLandrixXmlXsdLexicalRule): Boolean;
var
  CodePoints: TLandrixXmlCodePoints;
  I, C: Integer;
begin
  Result := False;
  CodePoints := LandrixXmlUtf8ToCodePoints(S);
  if Length(CodePoints) = 0 then
    Exit;
  for I := 0 to Integer(Length(CodePoints)) - 1 do
  begin
    C := CodePoints[I];
    if (Rule = xslNCName) and (C = Ord(':')) then
      Exit;
    if (I = 0) and (Rule <> xslNmToken) then
    begin
      if not (InRanges(XmlLetter4Ranges, C) or (C = Ord('_')) or (C = Ord(':'))) then
        Exit;
    end
    else if not InRanges(XmlNameChar4Ranges, C) then
      Exit;
  end;
  Result := True;
end;

{ binary32 rounding of a double (float value space), ties to even unless
  TieDirection says otherwise; Tie tells whether D lay exactly halfway
  between two floats. }
function RoundToFloat(const D: TLandrixXmlDouble; TieDirection: Integer; out Tie: Boolean): TLandrixXmlDouble;
var
  Bits, Mantissa, Kept, Rest, Half: Int64;
  Biased, Drop: Integer;
begin
  Result := D;
  Tie := False;
  Bits := D.Bits;
  Biased := Integer((Bits shr 52) and 2047);
  if (Biased = 2047) or ((Bits and not Low(Int64)) = 0) then
    Exit;
  { binary32: 24 significant bits, exponents -126 .. 127, subnormals to
    2^-149; in binary64 terms a biased exponent of 1023 - 126 = 897 }
  if Biased > 1023 + 127 then
  begin
    { 2^128 and above }
    Result := LandrixXmlDoubleInfinity(Bits < 0);
    Exit;
  end;
  if Biased = 0 then
  begin
    Result := LandrixXmlDoubleZero(Bits < 0);
    Exit;
  end;
  Mantissa := (Bits and Int64($000FFFFFFFFFFFFF)) or Int64($0010000000000000);
  { bits to drop from the 53-bit significand }
  if Biased >= 1023 - 126 then
    Drop := 29
  else
    Drop := 29 + (1023 - 126 - Biased);
  if Drop > 54 then
  begin
    Result := LandrixXmlDoubleZero(Bits < 0);
    Exit;
  end;
  Kept := Mantissa shr Drop;
  Rest := Mantissa - (Kept shl Drop);
  Half := Int64(1) shl (Drop - 1);
  Tie := Rest = Half;
  { a tie goes to even, or away from zero / towards zero if the exact value
    is known to lie above / below the double (TieDirection 1 / -1) }
  if (Rest > Half) or (Tie and (((TieDirection = 0) and Odd(Kept)) or (TieDirection > 0))) then
    Inc(Kept);
  Mantissa := Kept shl Drop;
  { renormalize: a carry may raise the exponent }
  while Mantissa >= Int64($0020000000000000) do
  begin
    Mantissa := Mantissa shr 1;
    Inc(Biased);
  end;
  if Mantissa = 0 then
  begin
    Result := LandrixXmlDoubleZero(Bits < 0);
    Exit;
  end;
  while Mantissa < Int64($0010000000000000) do
  begin
    Mantissa := Mantissa shl 1;
    Dec(Biased);
  end;
  if Biased > 1023 + 127 then
  begin
    Result := LandrixXmlDoubleInfinity(Bits < 0);
    Exit;
  end;
  Result.Bits := (Bits and Low(Int64)) or (Int64(Biased) shl 52) or (Mantissa and Int64($000FFFFFFFFFFFFF));
end;

{ The float nearest to the number written in Text, given D, the double
  nearest to it. Rounding D again would round twice; that matters only if
  D lies exactly halfway between two floats, and then the exact value of
  Text decides (as Java parses floats directly to binary32). }
function FloatFromLexical(const Text: TLandrixXmlUtf8; const D: TLandrixXmlDouble): TLandrixXmlDouble;
var
  Tie, Negative: Boolean;
  P, E, I, Digits: Integer;
  Mantissa, Exact, Approx: TLandrixXmlDecimal;
  C: Integer;
begin
  Result := RoundToFloat(D, 0, Tie);
  if not Tie then
    Exit;
  { exact decimal value of Text: mantissa times 10^exponent }
  P := 0;
  for I := 1 to Length(Text) do
    if (Text[I] = 'e') or (Text[I] = 'E') then
    begin
      P := I;
      Break;
    end;
  if P = 0 then
  begin
    if not LandrixXmlTryParseDecimal(Text, Exact) then
      Exit;
  end
  else
  begin
    if not LandrixXmlTryParseDecimal(Copy(Text, 1, P - 1), Mantissa) then
      Exit;
    { exponent: sign, digits; an exponent of more than six significant
      digits cannot give a value in the float range, so no tie }
    Negative := False;
    I := P + 1;
    if (I <= Length(Text)) and ((Text[I] = '+') or (Text[I] = '-')) then
    begin
      Negative := Text[I] = '-';
      Inc(I);
    end;
    E := 0;
    Digits := 0;
    while I <= Length(Text) do
    begin
      if (E > 0) or (Text[I] <> '0') then
        Inc(Digits);
      if Digits > 6 then
        Exit;
      E := E * 10 + (Ord(Text[I]) - Ord('0'));
      Inc(I);
    end;
    if Negative then
      E := -E;
    Exact := LandrixXmlDecimalMultiplyPow10(Mantissa, E);
  end;
  Approx := LandrixXmlDoubleToDecimal(D);
  C := LandrixXmlDecimalCompare(LandrixXmlDecimalAbs(Exact), LandrixXmlDecimalAbs(Approx));
  if C <> 0 then
    Result := RoundToFloat(D, C, Tie);
end;

{ The lexical check of a primitive type; Normalized is already white space
  processed. }
function ParsePrimitive(Primitive: TLandrixXmlXsdPrimitive; Rule: TLandrixXmlXsdLexicalRule;
  const Normalized: TLandrixXmlUtf8; out Value: TLandrixXmlXsdValue): Boolean;
var
  I: Integer;
begin
  Result := False;
  Value.Primitive := Primitive;
  Value.Text := Normalized;
  Value.Length := Utf16Length(Normalized);
  Value.DecimalValue := LandrixXmlDecimalZero;
  Value.DoubleValue := LandrixXmlDoubleZero(False);
  Value.BooleanValue := False;
  Value.DateTime.Year := 0;
  Value.DateTime.Month := 0;
  Value.DateTime.Day := 0;
  Value.DateTime.Hour := 0;
  Value.DateTime.Minute := 0;
  Value.DateTime.Second := LandrixXmlDecimalZero;
  Value.DateTime.HasTimeZone := False;
  Value.DateTime.TimeZone := 0;
  case Primitive of
    xspAnySimpleType, xspString:
      case Rule of
        xslLanguage: Result := IsLanguage(Normalized);
        xslName, xslNCName, xslNmToken: Result := IsNameKind(Normalized, Rule);
      else
        Result := True;
      end;
    xspBoolean:
      begin
        if (Normalized = 'true') or (Normalized = '1') then
        begin
          Value.BooleanValue := True;
          Result := True;
        end
        else if (Normalized = 'false') or (Normalized = '0') then
          Result := True;
      end;
    xspDecimal:
      if Rule = xslInteger then
        Result := LandrixXmlTryParseDecimalInteger(Normalized, Value.DecimalValue)
      else
        Result := LandrixXmlTryParseDecimal(Normalized, Value.DecimalValue);
    xspFloat, xspDouble:
      begin
        { XML Schema 1.0 has no "+INF" }
        if Normalized = '+INF' then
          Exit;
        Result := LandrixXmlDoubleTryParse(Normalized, Value.DoubleValue);
        if Result and (Primitive = xspFloat) then
          Value.DoubleValue := FloatFromLexical(Normalized, Value.DoubleValue);
      end;
    xspDateTime, xspTime, xspDate, xspGYearMonth, xspGYear, xspGMonthDay, xspGDay, xspGMonth:
      Result := ParseDateTimeKind(Normalized, Primitive, Value.DateTime);
    xspHexBinary:
      begin
        if Length(Normalized) mod 2 <> 0 then
          Exit;
        for I := 1 to Length(Normalized) do
          if HexValue(AnsiChar(Normalized[I])) < 0 then
            Exit;
        Value.Length := Length(Normalized) div 2;
        Result := True;
      end;
    xspBase64Binary:
      begin
        Value.Length := Base64Length(Normalized);
        Result := Value.Length >= 0;
      end;
    xspAnyURI:
      Result := IsValidUri(Normalized);
  end;
end;

{ ---------------------------------------------------------------------- }
{ Comparison                                                             }
{ ---------------------------------------------------------------------- }

function CompareInt(A, B: Integer): Integer;
begin
  if A < B then
    Result := -1
  else if A > B then
    Result := 1
  else
    Result := 0;
end;

{ Minutes since an arbitrary origin, ignoring the time zone; days counted
  on the proleptic Gregorian calendar. }
function DayNumber(Year, Month, Day: Integer): Int64;
var
  Y, M: Int64;
begin
  { days from civil, shifted so that March is the first month; the offset
    of 400000 years (a whole number of 400-year cycles) keeps Y positive,
    so div rounds down, and only differences of day numbers are used }
  Y := Int64(Year) + 400000;
  M := Month;
  if M <= 2 then
  begin
    Dec(Y);
    Inc(M, 12);
  end;
  Result := 365 * Y + (Y div 4) - (Y div 100) + (Y div 400) + (153 * (M - 3) + 2) div 5 + Day;
end;

{ Minutes, then seconds. }
function CompareInstant(MinutesA: Int64; const SecondA: TLandrixXmlDecimal; MinutesB: Int64;
  const SecondB: TLandrixXmlDecimal): Integer;
begin
  if MinutesA < MinutesB then
    Result := -1
  else if MinutesA > MinutesB then
    Result := 1
  else
    Result := LandrixXmlDecimalCompare(SecondA, SecondB);
end;

function CompareDateTime(const A, B: TLandrixXmlXsdDateTime; Kind: TLandrixXmlXsdPrimitive): Integer;
var
  MA, MB: Int64;
  YA, YB, DA, DB: Integer;
begin
  { missing parts get fixed reference values }
  YA := A.Year;
  YB := B.Year;
  if not (Kind in [xspDateTime, xspDate, xspGYearMonth, xspGYear]) then
  begin
    YA := 1972;
    YB := 1972;
  end;
  DA := A.Day;
  DB := B.Day;
  if DA = 0 then
    DA := 1;
  if DB = 0 then
    DB := 1;
  if A.Month = 0 then
    MA := DayNumber(YA, 1, DA)
  else
    MA := DayNumber(YA, A.Month, DA);
  if B.Month = 0 then
    MB := DayNumber(YB, 1, DB)
  else
    MB := DayNumber(YB, B.Month, DB);
  MA := MA * 1440 + Int64(A.Hour) * 60 + A.Minute - A.TimeZone;
  MB := MB * 1440 + Int64(B.Hour) * 60 + B.Minute - B.TimeZone;
  if A.HasTimeZone <> B.HasTimeZone then
  begin
    { XML Schema 1.0, 3.2.7.4: a value without time zone may lie anywhere
      between +14:00 and -14:00; only a difference beyond that orders them.
      Compared with seconds, as Xerces does. }
    if A.HasTimeZone then
    begin
      if CompareInstant(MA, A.Second, MB - 14 * 60, B.Second) < 0 then
        Result := -1
      else if CompareInstant(MA, A.Second, MB + 14 * 60, B.Second) > 0 then
        Result := 1
      else
        Result := LandrixXmlXsdIncomparable;
    end
    else
    begin
      if CompareInstant(MA + 14 * 60, A.Second, MB, B.Second) < 0 then
        Result := -1
      else if CompareInstant(MA - 14 * 60, A.Second, MB, B.Second) > 0 then
        Result := 1
      else
        Result := LandrixXmlXsdIncomparable;
    end;
  end
  else
    Result := CompareInstant(MA, A.Second, MB, B.Second);
end;

function WithoutSpaces(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I, N: Integer;
begin
  Result := '';
  SetLength(Result, Length(S));
  N := 0;
  for I := 1 to Length(S) do
    if S[I] <> ' ' then
    begin
      Inc(N);
      Result[N] := S[I];
    end;
  SetLength(Result, N);
end;

{ hexBinary values are equal regardless of the case of the digits }
function SameHex(const A, B: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for I := 1 to Length(A) do
      if HexValue(AnsiChar(A[I])) <> HexValue(AnsiChar(B[I])) then
      begin
        Result := False;
        Exit;
      end;
end;

function LandrixXmlXsdCompareValues(const A, B: TLandrixXmlXsdValue): Integer;
begin
  Result := LandrixXmlXsdIncomparable;
  if A.Primitive <> B.Primitive then
    Exit;
  case A.Primitive of
    xspDecimal:
      Result := LandrixXmlDecimalCompare(A.DecimalValue, B.DecimalValue);
    xspFloat, xspDouble:
      begin
        Result := LandrixXmlDoubleCompare(A.DoubleValue, B.DoubleValue);
        { NaN equals itself in the value space of XML Schema 1.0 }
        if (Result = LandrixXmlDoubleUnordered) and LandrixXmlDoubleIsNaN(A.DoubleValue) and
          LandrixXmlDoubleIsNaN(B.DoubleValue) then
          Result := 0
        else if Result = LandrixXmlDoubleUnordered then
          Result := LandrixXmlXsdIncomparable;
      end;
    xspBoolean:
      Result := CompareInt(Ord(A.BooleanValue), Ord(B.BooleanValue));
    xspDateTime, xspTime, xspDate, xspGYearMonth, xspGYear, xspGMonthDay, xspGDay, xspGMonth:
      Result := CompareDateTime(A.DateTime, B.DateTime, A.Primitive);
  else
    { strings, URIs, binary: equality only, by the normalized lexical
      form (binary values compare case-insensitively for hex) }
    if A.Primitive = xspHexBinary then
    begin
      if SameHex(A.Text, B.Text) then
        Result := 0;
    end
    else if A.Primitive = xspBase64Binary then
    begin
      { the same octets: spaces do not count }
      if WithoutSpaces(A.Text) = WithoutSpaces(B.Text) then
        Result := 0;
    end
    else if A.Text = B.Text then
      Result := 0;
  end;
end;

{ ---------------------------------------------------------------------- }
{ TLandrixXmlXsdSimpleType                                                  }
{ ---------------------------------------------------------------------- }

procedure ClearBound(var B: TLandrixXmlXsdBound);
begin
  B.Present := False;
end;

procedure TLandrixXmlXsdSimpleType.InitFacets;
begin
  FLength := -1;
  FMinLength := -1;
  FMaxLength := -1;
  FPatterns := nil;
  FEnumeration := nil;
  FEnumerationCount := 0;
  ClearBound(FMinInclusive);
  ClearBound(FMaxInclusive);
  ClearBound(FMinExclusive);
  ClearBound(FMaxExclusive);
  FTotalDigits := -1;
  FFractionDigits := -1;
end;

constructor TLandrixXmlXsdSimpleType.CreateBuiltin(const Name: TLandrixXmlUtf8; Base: TLandrixXmlXsdSimpleType;
  Primitive: TLandrixXmlXsdPrimitive; WhiteSpace: TLandrixXmlXsdWhiteSpace;
  LexicalRule: TLandrixXmlXsdLexicalRule);
begin
  inherited Create;
  InitFacets;
  FNamespaceUri := LandrixXmlXsdNamespace;
  FName := Name;
  FBase := Base;
  FVariety := xsvAtomic;
  FPrimitive := Primitive;
  FWhiteSpace := WhiteSpace;
  FLexicalRule := LexicalRule;
  FBuiltin := True;
end;

constructor TLandrixXmlXsdSimpleType.CreateRestriction(Base: TLandrixXmlXsdSimpleType;
  const NamespaceUri, Name: TLandrixXmlUtf8);
begin
  inherited Create;
  InitFacets;
  if Base = nil then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'A restriction needs a base type');
  FNamespaceUri := NamespaceUri;
  FName := Name;
  FBase := Base;
  FVariety := Base.FVariety;
  FPrimitive := Base.FPrimitive;
  FWhiteSpace := Base.FWhiteSpace;
  FLexicalRule := Base.FLexicalRule;
  FMembers := Base.FMembers;
end;

constructor TLandrixXmlXsdSimpleType.CreateUnion(const Members: array of TLandrixXmlXsdSimpleType;
  const NamespaceUri, Name: TLandrixXmlUtf8);
var
  I: Integer;
begin
  inherited Create;
  InitFacets;
  FNamespaceUri := NamespaceUri;
  FName := Name;
  FBase := LandrixXmlXsdBuiltinType('anySimpleType');
  FVariety := xsvUnion;
  FPrimitive := xspAnySimpleType;
  FWhiteSpace := xwsPreserve;
  SetLength(FMembers, Length(Members));
  for I := 0 to Integer(High(Members)) do
  begin
    if Members[I] = nil then
      raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'Union member type missing');
    FMembers[I] := Members[I];
  end;
end;

destructor TLandrixXmlXsdSimpleType.Destroy;
begin
  FPatterns.Free;
  inherited Destroy;
end;

function TLandrixXmlXsdSimpleType.DisplayName: string;
var
  T: TLandrixXmlXsdSimpleType;
begin
  if (FName = '') and (FAnonymousName <> '') then
  begin
    Result := LandrixXmlUtf8ToString(FAnonymousName);
    Exit;
  end;
  T := Self;
  while (T <> nil) and (T.FName = '') do
    T := T.FBase;
  if T = Self then
    Result := LandrixXmlUtf8ToString(FName)
  else if T <> nil then
    Result := '#AnonType_' + LandrixXmlUtf8ToString(T.FName)
  else
    Result := '#AnonType';
end;

function TLandrixXmlXsdSimpleType.IsDerivedFrom(AType: TLandrixXmlXsdSimpleType): Boolean;
var
  T: TLandrixXmlXsdSimpleType;
begin
  T := Self;
  while T <> nil do
  begin
    if T = AType then
    begin
      Result := True;
      Exit;
    end;
    T := T.FBase;
  end;
  Result := False;
end;

function NonNegativeFacet(const Text: TLandrixXmlUtf8; Positive: Boolean): Integer;
var
  D: TLandrixXmlDecimal;
  V: Int64;
begin
  if not LandrixXmlTryParseDecimalInteger(Text, D) or not LandrixXmlDecimalTryToInt64(D, V) or
    (V < 0) or (Positive and (V = 0)) or (V > MaxInt) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'Invalid facet value ' + Quote(Text));
  Result := Integer(V);
end;

function TLandrixXmlXsdSimpleType.ParseFacetValue(const Text: TLandrixXmlUtf8): TLandrixXmlXsdValue;
var
  Error: TLandrixXmlXsdError;
begin
  { a facet value must be valid for the base type }
  if not FBase.Validate(Text, Result, Error) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'Facet value ' + Quote(Text) +
      ' is not valid for the base type: ' + Error.Message);
end;

{ XML Schema 1.0 Part 2, 4.1.5 (cos-applicable-facets) }
function FacetApplies(Primitive: TLandrixXmlXsdPrimitive; Facet: TLandrixXmlXsdFacet): Boolean;
begin
  case Primitive of
    xspAnySimpleType, xspString, xspHexBinary, xspBase64Binary, xspAnyURI:
      Result := Facet in [xsfLength, xsfMinLength, xsfMaxLength, xsfPattern, xsfEnumeration, xsfWhiteSpace];
    xspBoolean:
      Result := Facet in [xsfPattern, xsfWhiteSpace];
    xspDecimal:
      Result := Facet in [xsfPattern, xsfEnumeration, xsfWhiteSpace, xsfMaxInclusive, xsfMaxExclusive,
        xsfMinInclusive, xsfMinExclusive, xsfTotalDigits, xsfFractionDigits];
  else
    { float, double, date and time types }
    Result := Facet in [xsfPattern, xsfEnumeration, xsfWhiteSpace, xsfMaxInclusive, xsfMaxExclusive,
      xsfMinInclusive, xsfMinExclusive];
  end;
end;

procedure TLandrixXmlXsdSimpleType.AddFacet(Facet: TLandrixXmlXsdFacet; const Value: TLandrixXmlUtf8);
var
  V: TLandrixXmlXsdValue;
  Mode: TLandrixXmlXsdWhiteSpace;
begin
  if FVariety = xsvUnion then
    raise ELandrixXmlError.CreateCode(xecUnsupported, 'Facets on union types are not supported');
  if FBuiltin then
    raise ELandrixXmlError.CreateCode(xecInvalidOperation, 'Built-in types cannot get facets');
  if not FacetApplies(FPrimitive, Facet) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument,
      'Facet not allowed for this type (cos-applicable-facets)');
  case Facet of
    xsfLength: FLength := NonNegativeFacet(Value, False);
    xsfMinLength: FMinLength := NonNegativeFacet(Value, False);
    xsfMaxLength: FMaxLength := NonNegativeFacet(Value, False);
    xsfTotalDigits: FTotalDigits := NonNegativeFacet(Value, True);
    xsfFractionDigits: FFractionDigits := NonNegativeFacet(Value, False);
    xsfPattern:
      begin
        if FPatterns = nil then
          FPatterns := TObjectList.Create(True);
        FPatterns.Add(TLandrixXmlRegex.Create(Value, xrmXsd));
      end;
    xsfEnumeration:
      begin
        V := ParseFacetValue(Value);
        if FEnumerationCount = Length(FEnumeration) then
          SetLength(FEnumeration, 2 * FEnumerationCount + 8);
        FEnumeration[FEnumerationCount] := V;
        Inc(FEnumerationCount);
      end;
    xsfWhiteSpace:
      begin
        if Value = 'preserve' then
          Mode := xwsPreserve
        else if Value = 'replace' then
          Mode := xwsReplace
        else if Value = 'collapse' then
          Mode := xwsCollapse
        else
          raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'Invalid whiteSpace value ' + Quote(Value));
        if (FPrimitive <> xspString) and (FPrimitive <> xspAnySimpleType) and (Mode <> xwsCollapse) then
          raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'whiteSpace must be collapse for this type');
        if Mode < FBase.FWhiteSpace then
          raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'whiteSpace cannot be weaker than the base type''s');
        FWhiteSpace := Mode;
      end;
    xsfMaxInclusive:
      begin
        FMaxInclusive.Value := ParseFacetValue(Value);
        FMaxInclusive.Present := True;
      end;
    xsfMaxExclusive:
      begin
        FMaxExclusive.Value := ParseFacetValue(Value);
        FMaxExclusive.Present := True;
      end;
    xsfMinInclusive:
      begin
        FMinInclusive.Value := ParseFacetValue(Value);
        FMinInclusive.Present := True;
      end;
    xsfMinExclusive:
      begin
        FMinExclusive.Value := ParseFacetValue(Value);
        FMinExclusive.Present := True;
      end;
  end;
end;

function TLandrixXmlXsdSimpleType.CheckPatterns(const Value: TLandrixXmlXsdValue; const TypeName: string;
  out Error: TLandrixXmlXsdError): Boolean;
var
  I: Integer;
begin
  Result := True;
  if FPatterns = nil then
    Exit;
  for I := 0 to Integer(FPatterns.Count) - 1 do
    if TLandrixXmlRegex(FPatterns[I]).Matches(Value.Text) then
      Exit;
  Result := False;
  SetError(Error, 'cvc-pattern-valid', 'Value ' + Quote(Value.Text) +
    ' is not facet-valid with respect to pattern ' +
    Quote(TLandrixXmlRegex(FPatterns[0]).Source) + ' for type ''' + TypeName + '''.');
end;

{ --- canonical forms and keys as Xerces has them ---------------------- }

function XercesMaxDay(Year, Month: Integer): Integer;
begin
  if (Month = 4) or (Month = 6) or (Month = 9) or (Month = 11) then
    Result := 30
  else if Month = 2 then
  begin
    if (Year mod 4 = 0) and ((Year mod 100 <> 0) or (Year mod 400 = 0)) then
      Result := 29
    else
      Result := 28;
  end
  else
    Result := 31;
end;

function FloorDiv(A, B: Integer): Integer;
begin
  Result := A div B;
  if (A mod B <> 0) and ((A < 0) <> (B < 0)) then
    Dec(Result);
end;

function ValuePrimitive(const Value: TLandrixXmlXsdValue): TLandrixXmlXsdPrimitive;
begin
  Result := Value.Primitive;
  if Value.MemberType <> nil then
    Result := Value.MemberType.Primitive;
end;

{ The fields of a date or time value as Xerces keeps them: missing parts
  get its placeholders (year 2000, month 1, day 1, or 15 for xs:time),
  24:00:00 is the start of the next day, and a value with a time zone is
  moved to UTC the way Xerces' normalize does it. }
function XercesDateTime(const Value: TLandrixXmlXsdValue): TLandrixXmlXsdDateTime;
var
  Kind: TLandrixXmlXsdPrimitive;
  Temp, Carry, MaxDay: Integer;
begin
  Kind := ValuePrimitive(Value);
  Result := Value.DateTime;
  if not (Kind in [xspDateTime, xspDate, xspGYearMonth, xspGYear]) then
    Result.Year := 2000;
  if Result.Month = 0 then
    Result.Month := 1;
  if Result.Day = 0 then
  begin
    if Kind = xspTime then
      Result.Day := 15
    else
      Result.Day := 1;
  end;
  if Result.Hour = 24 then
  begin
    Result.Hour := 0;
    Inc(Result.Day);
    if Result.Day > XercesMaxDay(Result.Year, Result.Month) then
    begin
      Result.Day := 1;
      Inc(Result.Month);
      if Result.Month > 12 then
      begin
        Result.Month := 1;
        Inc(Result.Year);
        if Result.Year = 0 then
          Result.Year := 1;
      end;
    end;
  end;
  if not Result.HasTimeZone or (Result.TimeZone = 0) then
    Exit;
  Temp := Result.Minute - Result.TimeZone mod 60;
  Carry := FloorDiv(Temp, 60);
  Result.Minute := Temp - Carry * 60;
  Temp := Result.Hour - Result.TimeZone div 60 + Carry;
  Carry := FloorDiv(Temp, 24);
  Result.Hour := Temp - Carry * 24;
  Result.Day := Result.Day + Carry;
  while True do
  begin
    MaxDay := XercesMaxDay(Result.Year, Result.Month);
    if Result.Day < 1 then
    begin
      Result.Day := Result.Day + XercesMaxDay(Result.Year, Result.Month - 1);
      Carry := -1;
    end
    else if Result.Day > MaxDay then
    begin
      Result.Day := Result.Day - MaxDay;
      Carry := 1;
    end
    else
      Break;
    Temp := Result.Month + Carry;
    Result.Month := Temp - 1 - FloorDiv(Temp - 1, 12) * 12 + 1;
    Result.Year := Result.Year + FloorDiv(Temp - 1, 12);
    if Result.Year = 0 then
    begin
      if Result.TimeZone < 0 then
        Result.Year := 1
      else
        Result.Year := -1;
    end;
  end;
end;

function Digits2(Value: Integer): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(IntToStr(Value));
  if (Value >= 0) and (Value < 10) then
    Result := '0' + Result;
end;

function YearText(Year: Integer): TLandrixXmlUtf8;
var
  Sign: TLandrixXmlUtf8;
begin
  Sign := '';
  if Year < 0 then
  begin
    Sign := '-';
    Year := -Year;
  end;
  Result := LandrixXmlStringToUtf8(IntToStr(Year));
  while Length(Result) < 4 do
    Result := '0' + Result;
  Result := Sign + Result;
end;

{ Xerces' dateToString of the type. }
function DateTimeText(const Value: TLandrixXmlXsdValue): TLandrixXmlUtf8;
var
  D: TLandrixXmlXsdDateTime;
  Seconds: TLandrixXmlUtf8;
begin
  D := XercesDateTime(Value);
  Seconds := LandrixXmlFormatDecimal(D.Second);
  if LandrixXmlDecimalCompare(D.Second, LandrixXmlDecimalFromInt64(10)) < 0 then
    Seconds := '0' + Seconds;
  case ValuePrimitive(Value) of
    xspDateTime:
      Result := YearText(D.Year) + '-' + Digits2(D.Month) + '-' + Digits2(D.Day) + 'T' + Digits2(D.Hour) + ':' +
        Digits2(D.Minute) + ':' + Seconds;
    xspDate:
      Result := YearText(D.Year) + '-' + Digits2(D.Month) + '-' + Digits2(D.Day);
    xspTime:
      Result := Digits2(D.Hour) + ':' + Digits2(D.Minute) + ':' + Seconds;
    xspGYearMonth:
      Result := YearText(D.Year) + '-' + Digits2(D.Month);
    xspGYear:
      Result := YearText(D.Year);
    xspGMonthDay:
      Result := '--' + Digits2(D.Month) + '-' + Digits2(D.Day);
    xspGDay:
      Result := '---' + Digits2(D.Day);
  else
    Result := '--' + Digits2(D.Month);
  end;
  if D.HasTimeZone then
    Result := Result + 'Z';
end;

{ Java's Float.toString or Double.toString (the shortest digits that read
  back, the closest of them, at least two), written as Xerces' canonical
  form d.dddEn; "0.0E1" for zero. }
function FloatingText(const Value: TLandrixXmlXsdValue; IsFloat: Boolean): TLandrixXmlUtf8;
var
  D, Back: TLandrixXmlDouble;
  Exact, Digits, Rest, Floor, Ceil, Candidate, Mantissa: TLandrixXmlUtf8;
  I, Point, Exp10, P, MaxDigits, CeilExp: Integer;
  Sign: TLandrixXmlUtf8;
  FloorOk, CeilOk, Exact0: Boolean;

  function Text(const Ds: TLandrixXmlUtf8; E: Integer): TLandrixXmlUtf8;
  begin
    Result := Copy(Ds, 1, 1) + '.' + Copy(Ds, 2, MaxInt) + 'E' + LandrixXmlStringToUtf8(IntToStr(E));
  end;

  function ReadsBack(const Ds: TLandrixXmlUtf8; E: Integer): Boolean;
  var
    T: TLandrixXmlUtf8;
  begin
    T := Text(Ds, E);
    Back := LandrixXmlDoubleParse(T);
    if IsFloat then
      Back := FloatFromLexical(T, Back);
    Result := Back.Bits = D.Bits;
  end;

begin
  D := Value.DoubleValue;
  if LandrixXmlDoubleIsNaN(D) then
  begin
    Result := 'NaN';
    Exit;
  end;
  if LandrixXmlDoubleIsInfinite(D) then
  begin
    if LandrixXmlDoubleSignBit(D) then
      Result := '-INF'
    else
      Result := 'INF';
    Exit;
  end;
  if LandrixXmlDoubleIsZero(D) then
  begin
    Result := '0.0E1';
    Exit;
  end;
  Sign := '';
  if LandrixXmlDoubleSignBit(D) then
  begin
    Sign := '-';
    D := LandrixXmlDoubleNegate(D);
  end;
  { the exact value as significant digits and the exponent of the first }
  Exact := LandrixXmlFormatDecimal(LandrixXmlDoubleToDecimal(D));
  Point := Length(Exact) + 1;
  for I := 1 to Length(Exact) do
    if Exact[I] = '.' then
      Point := I;
  Digits := Copy(Exact, 1, Point - 1) + Copy(Exact, Point + 1, MaxInt);
  Exp10 := Point - 2;
  I := 1;
  while (I < Length(Digits)) and (Digits[I] = '0') do
  begin
    Inc(I);
    Dec(Exp10);
  end;
  Digits := Copy(Digits, I, MaxInt);
  if IsFloat then
    MaxDigits := 9
  else
    MaxDigits := 17;
  Mantissa := '';
  for P := 2 to MaxDigits do
  begin
    Floor := Copy(Digits, 1, P);
    while Length(Floor) < P do
      Floor := Floor + '0';
    Rest := Copy(Digits, P + 1, MaxInt);
    Exact0 := True;
    for I := 1 to Length(Rest) do
      if Rest[I] <> '0' then
        Exact0 := False;
    FloorOk := ReadsBack(Floor, Exp10);
    CeilOk := False;
    Ceil := '';
    CeilExp := Exp10;
    if not Exact0 then
    begin
      { the next decimal with P digits }
      Ceil := Floor;
      I := P;
      while (I >= 1) and (Ceil[I] = '9') do
      begin
        Ceil[I] := '0';
        Dec(I);
      end;
      if I >= 1 then
        Ceil[I] := AnsiChar(Ord(Ceil[I]) + 1)
      else
      begin
        Ceil := '1' + Copy(Ceil, 1, P - 1);
        Inc(CeilExp);
      end;
      CeilOk := ReadsBack(Ceil, CeilExp);
    end;
    if FloorOk and CeilOk then
    begin
      { the closer one; on a tie the one with the even last digit }
      Candidate := '5';
      while Length(Candidate) < Length(Rest) do
        Candidate := Candidate + '0';
      if (Rest > Candidate) or ((Rest = Candidate) and (Ord(Floor[P]) mod 2 = 1)) then
        FloorOk := False
      else
        CeilOk := False;
    end;
    if FloorOk then
    begin
      Mantissa := Floor;
      Break;
    end;
    if CeilOk then
    begin
      Mantissa := Ceil;
      Exp10 := CeilExp;
      Break;
    end;
  end;
  if Mantissa = '' then
    Mantissa := Copy(Digits, 1, MaxDigits);
  while (Length(Mantissa) > 1) and (Mantissa[Length(Mantissa)] = '0') do
    SetLength(Mantissa, Length(Mantissa) - 1);
  if Length(Mantissa) = 1 then
    Mantissa := Mantissa + '0';
  Result := Sign + Text(Mantissa, Exp10);
end;

function AsciiUpper(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if Result[I] in ['a'..'z'] then
      Result[I] := AnsiChar(Ord(Result[I]) - 32);
end;

function WithoutWhiteSpace(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I, N: Integer;
begin
  Result := '';
  SetLength(Result, Length(S));
  N := 0;
  for I := 1 to Length(S) do
    if not (S[I] in [' ', #9, #10, #13]) then
    begin
      Inc(N);
      Result[N] := S[I];
    end;
  SetLength(Result, N);
end;

function ValueTextAs(const Value: TLandrixXmlXsdValue; IsInteger: Boolean): TLandrixXmlUtf8;
var
  I: Integer;
  HasPoint: Boolean;
begin
  case ValuePrimitive(Value) of
    xspDecimal:
      begin
        Result := LandrixXmlFormatDecimal(Value.DecimalValue);
        if IsInteger then
          Exit;
        HasPoint := False;
        for I := 1 to Length(Result) do
          if Result[I] = '.' then
            HasPoint := True;
        if not HasPoint then
          Result := Result + '.0';
      end;
    xspBoolean:
      if Value.BooleanValue then
        Result := 'true'
      else
        Result := 'false';
    xspFloat:
      Result := FloatingText(Value, True);
    xspDouble:
      Result := FloatingText(Value, False);
    xspDateTime, xspTime, xspDate, xspGYearMonth, xspGYear, xspGMonthDay, xspGDay, xspGMonth:
      Result := DateTimeText(Value);
    xspHexBinary:
      Result := AsciiUpper(Value.Text);
    xspBase64Binary:
      Result := WithoutWhiteSpace(Value.Text);
  else
    Result := Value.Text;
  end;
end;

function LandrixXmlXsdValueText(const Value: TLandrixXmlXsdValue): TLandrixXmlUtf8;
begin
  Result := ValueTextAs(Value, (Value.MemberType <> nil) and (Value.MemberType.LexicalRule = xslInteger));
end;

function LandrixXmlXsdValueKey(const Value: TLandrixXmlXsdValue): TLandrixXmlUtf8;
var
  P: TLandrixXmlXsdPrimitive;
  D: TLandrixXmlXsdDateTime;
begin
  P := ValuePrimitive(Value);
  case P of
    xspDecimal:
      Result := LandrixXmlFormatDecimal(Value.DecimalValue);
    xspFloat, xspDouble:
      if LandrixXmlDoubleIsNaN(Value.DoubleValue) then
        Result := 'NaN'
      else if LandrixXmlDoubleIsZero(Value.DoubleValue) then
        Result := '0'
      else
        Result := LandrixXmlStringToUtf8(IntToHex(Value.DoubleValue.Bits, 16));
    xspDateTime, xspTime, xspDate, xspGYearMonth, xspGYear, xspGMonthDay, xspGDay, xspGMonth:
      begin
        D := XercesDateTime(Value);
        if D.HasTimeZone then
          Result := 'Z'
        else
          Result := 'L';
        Result := Result + LandrixXmlStringToUtf8(IntToStr(D.Year) + ':' + IntToStr(D.Month) + ':' +
          IntToStr(D.Day) + ':' + IntToStr(D.Hour) + ':' + IntToStr(D.Minute)) + ':' +
          LandrixXmlFormatDecimal(D.Second);
      end;
    xspBoolean, xspHexBinary, xspBase64Binary:
      Result := ValueTextAs(Value, False);
  else
    Result := Value.Text;
  end;
  Result := LandrixXmlStringToUtf8(IntToStr(Ord(P))) + ':' + Result;
end;

function EnumerationText(const Values: TLandrixXmlXsdValueArray; Count: Integer): string;
var
  I: Integer;
begin
  Result := '[';
  for I := 0 to Count - 1 do
  begin
    if I > 0 then
      Result := Result + ', ';
    Result := Result + LandrixXmlEscapeForMessage(LandrixXmlXsdValueText(Values[I]), MaxInt);
  end;
  Result := Result + ']';
end;

function LengthMessage(const Value: TLandrixXmlXsdValue; const Facet: string; Limit: Integer;
  const TypeName: string): string;
begin
  Result := 'Value ' + Quote(Value.Text) + ' with length = ''' + IntToStr(Value.Length) +
    ''' is not facet-valid with respect to ' + Facet + ' ''' + IntToStr(Limit) + ''' for type ''' +
    TypeName + '''.';
end;

{ T is the type that defines the bound. }
function BoundMessage(const Value: TLandrixXmlXsdValue; const Facet: string;
  const Bound: TLandrixXmlXsdBound; T: TLandrixXmlXsdSimpleType; const TypeName: string): string;
begin
  Result := 'Value ' + Quote(Value.Text) + ' is not facet-valid with respect to ' + Facet + ' ' +
    Quote(ValueTextAs(Bound.Value, T.LexicalRule = xslInteger)) + ' for type ''' + TypeName + '''.';
end;

{ The facets other than patterns, in the order in which Xerces checks its
  merged facets; for each kind the most derived type that defines it
  counts (a restriction can only narrow a facet). }
function TLandrixXmlXsdSimpleType.CheckFacets(const Value: TLandrixXmlXsdValue;
  out Error: TLandrixXmlXsdError): Boolean;
var
  T: TLandrixXmlXsdSimpleType;
  I, C, Digits: Integer;
  Found: Boolean;
  TypeName: string;
begin
  Result := False;
  TypeName := DisplayName;
  { maxLength }
  T := Self;
  while (T <> nil) and (T.FMaxLength < 0) do
    T := T.FBase;
  if (T <> nil) and (Value.Length > T.FMaxLength) then
  begin
    SetError(Error, 'cvc-maxLength-valid', LengthMessage(Value, 'maxLength', T.FMaxLength, TypeName));
    Exit;
  end;
  { minLength }
  T := Self;
  while (T <> nil) and (T.FMinLength < 0) do
    T := T.FBase;
  if (T <> nil) and (Value.Length < T.FMinLength) then
  begin
    SetError(Error, 'cvc-minLength-valid', LengthMessage(Value, 'minLength', T.FMinLength, TypeName));
    Exit;
  end;
  { length }
  T := Self;
  while (T <> nil) and (T.FLength < 0) do
    T := T.FBase;
  if (T <> nil) and (Value.Length <> T.FLength) then
  begin
    SetError(Error, 'cvc-length-valid', LengthMessage(Value, 'length', T.FLength, TypeName));
    Exit;
  end;
  { enumeration }
  T := Self;
  while (T <> nil) and (T.FEnumerationCount = 0) do
    T := T.FBase;
  if T <> nil then
  begin
    Found := False;
    for I := 0 to T.FEnumerationCount - 1 do
      if LandrixXmlXsdCompareValues(Value, T.FEnumeration[I]) = 0 then
      begin
        Found := True;
        Break;
      end;
    if not Found then
    begin
      SetError(Error, 'cvc-enumeration-valid', 'Value ' + Quote(Value.Text) +
        ' is not facet-valid with respect to enumeration ''' +
        EnumerationText(T.FEnumeration, T.FEnumerationCount) + '''. It must be a value from the enumeration.');
      Exit;
    end;
  end;
  if Value.Primitive = xspDecimal then
  begin
    { fractionDigits }
    T := Self;
    while (T <> nil) and (T.FFractionDigits < 0) do
      T := T.FBase;
    Digits := LandrixXmlDecimalFractionDigits(Value.DecimalValue);
    if (T <> nil) and (Digits > T.FFractionDigits) then
    begin
      SetError(Error, 'cvc-fractionDigits-valid', 'Value ' + Quote(Value.Text) + ' has ' +
        IntToStr(Digits) + ' fraction digits, but the number of fraction digits has been limited to ' +
        IntToStr(T.FFractionDigits) + '.');
      Exit;
    end;
    { totalDigits }
    T := Self;
    while (T <> nil) and (T.FTotalDigits < 0) do
      T := T.FBase;
    Digits := LandrixXmlDecimalTotalDigits(Value.DecimalValue);
    if (T <> nil) and (Digits > T.FTotalDigits) then
    begin
      SetError(Error, 'cvc-totalDigits-valid', 'Value ' + Quote(Value.Text) + ' has ' +
        IntToStr(Digits) + ' total digits, but the number of total digits has been limited to ' +
        IntToStr(T.FTotalDigits) + '.');
      Exit;
    end;
  end;
  { maxInclusive }
  T := Self;
  while (T <> nil) and not T.FMaxInclusive.Present do
    T := T.FBase;
  if T <> nil then
  begin
    C := LandrixXmlXsdCompareValues(Value, T.FMaxInclusive.Value);
    if (C = 1) or (C = LandrixXmlXsdIncomparable) then
    begin
      SetError(Error, 'cvc-maxInclusive-valid', BoundMessage(Value, 'maxInclusive', T.FMaxInclusive, T, TypeName));
      Exit;
    end;
  end;
  { maxExclusive }
  T := Self;
  while (T <> nil) and not T.FMaxExclusive.Present do
    T := T.FBase;
  if (T <> nil) and (LandrixXmlXsdCompareValues(Value, T.FMaxExclusive.Value) <> -1) then
  begin
    SetError(Error, 'cvc-maxExclusive-valid', BoundMessage(Value, 'maxExclusive', T.FMaxExclusive, T, TypeName));
    Exit;
  end;
  { minInclusive }
  T := Self;
  while (T <> nil) and not T.FMinInclusive.Present do
    T := T.FBase;
  if T <> nil then
  begin
    C := LandrixXmlXsdCompareValues(Value, T.FMinInclusive.Value);
    if (C = -1) or (C = LandrixXmlXsdIncomparable) then
    begin
      SetError(Error, 'cvc-minInclusive-valid', BoundMessage(Value, 'minInclusive', T.FMinInclusive, T, TypeName));
      Exit;
    end;
  end;
  { minExclusive }
  T := Self;
  while (T <> nil) and not T.FMinExclusive.Present do
    T := T.FBase;
  if (T <> nil) and (LandrixXmlXsdCompareValues(Value, T.FMinExclusive.Value) <> 1) then
  begin
    SetError(Error, 'cvc-minExclusive-valid', BoundMessage(Value, 'minExclusive', T.FMinExclusive, T, TypeName));
    Exit;
  end;
  Result := True;
end;

function TLandrixXmlXsdSimpleType.HasPatterns: Boolean;
var
  T: TLandrixXmlXsdSimpleType;
begin
  T := Self;
  while (T <> nil) and (T.FPatterns = nil) do
    T := T.FBase;
  Result := T <> nil;
end;

var
  IdTypeCache: TLandrixXmlXsdSimpleType = nil;
  IdRefTypeCache: TLandrixXmlXsdSimpleType = nil;

function TLandrixXmlXsdSimpleType.IsTrimmedType: Boolean;
begin
  if FPrimitive = xspString then
    Result := ((IdTypeCache <> nil) and IsDerivedFrom(IdTypeCache)) or
      ((IdRefTypeCache <> nil) and IsDerivedFrom(IdRefTypeCache))
  else
    Result := not (FPrimitive in [xspAnySimpleType, xspBase64Binary]);
end;

function Trimmed(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  First, Last: Integer;
begin
  First := 1;
  Last := Length(S);
  while (First <= Last) and IsXmlSpace(AnsiChar(S[First])) do
    Inc(First);
  while (Last >= First) and IsXmlSpace(AnsiChar(S[Last])) do
    Dec(Last);
  Result := Copy(S, First, Last - First + 1);
end;

{ The type name Xerces prints in cvc-datatype-valid.1.2.1: the built-in
  validator, which is 'integer' for all integer types and 'NCName' for ID
  and IDREF. }
function TLandrixXmlXsdSimpleType.ValidatorName: string;
var
  T: TLandrixXmlXsdSimpleType;
begin
  T := Self;
  while not T.FBuiltin do
    T := T.FBase;
  if T.FLexicalRule = xslInteger then
    Result := 'integer'
  else if T.FLexicalRule = xslNCName then
    Result := 'NCName'
  else
    Result := LandrixXmlUtf8ToString(T.FName);
end;

function TLandrixXmlXsdSimpleType.Validate(const Text: TLandrixXmlUtf8; out Value: TLandrixXmlXsdValue;
  out Error: TLandrixXmlXsdError): Boolean;
var
  Normalized: TLandrixXmlUtf8;
  T: TLandrixXmlXsdSimpleType;
  I: Integer;
  MemberError: TLandrixXmlXsdError;
  TypeName: string;
  Found: Boolean;
begin
  Result := False;
  Error.Code := '';
  Error.Message := '';
  if FVariety = xsvUnion then
  begin
    for I := 0 to Integer(Length(FMembers)) - 1 do
      if FMembers[I].Validate(Text, Value, MemberError) then
      begin
        Result := True;
        Exit;
      end;
    Value.RawText := Text;
    Value.MemberType := nil;
    SetError(Error, 'cvc-datatype-valid.1.2.3', Quote(Text) + ' is not a valid value of union type ''' +
      DisplayName + '''.');
    Exit;
  end;
  { Xerces collapses only string-based values; the others (numbers,
    booleans, dates, binary, anyURI, ID, IDREF) are only trimmed unless a
    pattern facet applies, which makes it collapse them first. Internal
    white space makes them invalid either way, but messages show it. }
  if (FWhiteSpace = xwsCollapse) and IsTrimmedType and not HasPatterns then
    Normalized := Trimmed(Text)
  else
    Normalized := LandrixXmlXsdNormalizeWhiteSpace(Text, FWhiteSpace);
  TypeName := DisplayName;
  { as Xerces: the patterns of all types first, on the lexical form }
  Value.Text := Normalized;
  Value.RawText := Text;
  Value.MemberType := Self;
  T := Self;
  while T <> nil do
  begin
    if not T.CheckPatterns(Value, TypeName, Error) then
      Exit;
    T := T.FBase;
  end;
  Found := ParsePrimitive(FPrimitive, FLexicalRule, Normalized, Value);
  Value.RawText := Text;
  Value.MemberType := Self;
  if not Found then
  begin
    { Xerces defines language by a pattern facet and reports that }
    if FLexicalRule = xslLanguage then
      SetError(Error, 'cvc-pattern-valid', 'Value ' + Quote(Normalized) +
        ' is not facet-valid with respect to pattern ''([a-zA-Z]{1,8})(-[a-zA-Z0-9]{1,8})*'' for type ''' +
        TypeName + '''.')
    else
      SetError(Error, 'cvc-datatype-valid.1.2.1', Quote(Normalized) + ' is not a valid value for ''' +
        ValidatorName + '''.');
    Exit;
  end;
  Result := CheckFacets(Value, Error);
end;

{ ---------------------------------------------------------------------- }
{ Built-in types                                                         }
{ ---------------------------------------------------------------------- }

var
  BuiltinTypes: TObjectList = nil;

function Find(const LocalName: TLandrixXmlUtf8): TLandrixXmlXsdSimpleType;
var
  I: Integer;
begin
  for I := 0 to Integer(BuiltinTypes.Count) - 1 do
  begin
    Result := TLandrixXmlXsdSimpleType(BuiltinTypes[I]);
    if Result.FName = LocalName then
      Exit;
  end;
  Result := nil;
end;

function Add(const Name: TLandrixXmlUtf8; const BaseName: TLandrixXmlUtf8;
  Primitive: TLandrixXmlXsdPrimitive; WhiteSpace: TLandrixXmlXsdWhiteSpace;
  Rule: TLandrixXmlXsdLexicalRule): TLandrixXmlXsdSimpleType;
var
  Base: TLandrixXmlXsdSimpleType;
begin
  if BaseName = '' then
    Base := nil
  else
    Base := Find(BaseName);
  Result := TLandrixXmlXsdSimpleType.CreateBuiltin(Name, Base, Primitive, WhiteSpace, Rule);
  BuiltinTypes.Add(Result);
end;

{ An integer type with bounds; '' for no bound. }
procedure AddInteger(const Name, BaseName, MinValue, MaxValue: TLandrixXmlUtf8);
var
  T: TLandrixXmlXsdSimpleType;
begin
  T := Add(Name, BaseName, xspDecimal, xwsCollapse, xslInteger);
  if MinValue <> '' then
  begin
    T.FMinInclusive.Present := True;
    ParsePrimitive(xspDecimal, xslInteger, MinValue, T.FMinInclusive.Value);
  end;
  if MaxValue <> '' then
  begin
    T.FMaxInclusive.Present := True;
    ParsePrimitive(xspDecimal, xslInteger, MaxValue, T.FMaxInclusive.Value);
  end;
end;

procedure CreateBuiltinTypes;
begin
  BuiltinTypes := TObjectList.Create(True);
  Add('anySimpleType', '', xspAnySimpleType, xwsPreserve, xslNone);
  Add('string', 'anySimpleType', xspString, xwsPreserve, xslNone);
  Add('normalizedString', 'string', xspString, xwsReplace, xslNone);
  Add('token', 'normalizedString', xspString, xwsCollapse, xslNone);
  Add('language', 'token', xspString, xwsCollapse, xslLanguage);
  Add('Name', 'token', xspString, xwsCollapse, xslName);
  Add('NCName', 'Name', xspString, xwsCollapse, xslNCName);
  Add('ID', 'NCName', xspString, xwsCollapse, xslNCName);
  Add('IDREF', 'NCName', xspString, xwsCollapse, xslNCName);
  Add('NMTOKEN', 'token', xspString, xwsCollapse, xslNmToken);
  Add('boolean', 'anySimpleType', xspBoolean, xwsCollapse, xslNone);
  Add('decimal', 'anySimpleType', xspDecimal, xwsCollapse, xslNone);
  AddInteger('integer', 'decimal', '', '');
  AddInteger('nonPositiveInteger', 'integer', '', '0');
  AddInteger('negativeInteger', 'nonPositiveInteger', '', '-1');
  AddInteger('long', 'integer', '-9223372036854775808', '9223372036854775807');
  AddInteger('int', 'long', '-2147483648', '2147483647');
  AddInteger('short', 'int', '-32768', '32767');
  AddInteger('byte', 'short', '-128', '127');
  AddInteger('nonNegativeInteger', 'integer', '0', '');
  AddInteger('unsignedLong', 'nonNegativeInteger', '', '18446744073709551615');
  AddInteger('unsignedInt', 'unsignedLong', '', '4294967295');
  AddInteger('unsignedShort', 'unsignedInt', '', '65535');
  AddInteger('unsignedByte', 'unsignedShort', '', '255');
  AddInteger('positiveInteger', 'nonNegativeInteger', '1', '');
  Add('float', 'anySimpleType', xspFloat, xwsCollapse, xslNone);
  Add('double', 'anySimpleType', xspDouble, xwsCollapse, xslNone);
  Add('dateTime', 'anySimpleType', xspDateTime, xwsCollapse, xslNone);
  Add('time', 'anySimpleType', xspTime, xwsCollapse, xslNone);
  Add('date', 'anySimpleType', xspDate, xwsCollapse, xslNone);
  Add('gYearMonth', 'anySimpleType', xspGYearMonth, xwsCollapse, xslNone);
  Add('gYear', 'anySimpleType', xspGYear, xwsCollapse, xslNone);
  Add('gMonthDay', 'anySimpleType', xspGMonthDay, xwsCollapse, xslNone);
  Add('gDay', 'anySimpleType', xspGDay, xwsCollapse, xslNone);
  Add('gMonth', 'anySimpleType', xspGMonth, xwsCollapse, xslNone);
  Add('hexBinary', 'anySimpleType', xspHexBinary, xwsCollapse, xslNone);
  Add('base64Binary', 'anySimpleType', xspBase64Binary, xwsCollapse, xslNone);
  Add('anyURI', 'anySimpleType', xspAnyURI, xwsCollapse, xslNone);
end;

function LandrixXmlXsdBuiltinType(const LocalName: TLandrixXmlUtf8): TLandrixXmlXsdSimpleType;
begin
  Result := Find(LocalName);
end;

initialization
  { created here, not on first use, so that concurrent readers are safe }
  CreateBuiltinTypes;
  IdTypeCache := Find('ID');
  IdRefTypeCache := Find('IDREF');

finalization
  BuiltinTypes.Free;

end.
