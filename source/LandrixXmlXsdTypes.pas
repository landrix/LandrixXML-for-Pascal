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
  A list collapses white space, checks its patterns on the whole value,
  then each item (separated by spaces) with its item type, then its
  length facets (counting items) and enumeration.

  Built-in types: anySimpleType, string, normalizedString, token,
  language, Name, NCName, ID, IDREF, ENTITY, NMTOKEN, boolean, decimal, integer and
  its twelve derived types, float, double, dateTime, time, date,
  gYearMonth, gYear, gMonthDay, gDay, gMonth, duration, hexBinary,
  base64Binary, anyURI, QName, NOTATION, and the list types NMTOKENS,
  IDREFS and ENTITIES. An ENTITY value is checked here as an NCName; that
  it names an unparsed entity of the document is checked by the
  validator, as ID and IDREF values are.

  A duration is parsed and ordered as Xerces does: whole numbers up to
  2147483647, seconds with a fraction (also ".5S"); the order adds both
  durations to the four dates of XML Schema 1.0, 3.2.6.2 with Xerces'
  arithmetic (Java int overflow and the float division of its fQuotient
  included) and is defined only if all four agree, so P1M and P30D are
  incomparable and not equal, P1D and PT24H are equal. The seconds are
  exact decimals where Xerces uses doubles.

  A QName value is resolved with the namespace context given to Validate
  (TLandrixXmlXsdNamespaceContext): no prefix stands for the default
  namespace, an undeclared prefix is the error UndeclaredPrefix. Two
  QNames are equal if namespace and local name are; the length facets do
  not apply to them (Xerces). A NOTATION value is checked as a QName (the
  schema loader makes sure that its enumeration names notations).

  A restriction of a union may have pattern and enumeration facets
  (Xerces): the patterns apply to the value with collapsed white space,
  then the member types are tried in order, then the enumeration compares
  the value of the member type that accepted it.

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
    xspHexBinary, xspBase64Binary, xspAnyURI, xspQName, xspDuration,
    xspNotation
  );

  { Lexical rules of built-in types derived from string or decimal. }
  TLandrixXmlXsdLexicalRule = (xslNone, xslLanguage, xslName, xslNCName, xslNmToken, xslInteger);

  TLandrixXmlXsdFacet = (
    xsfLength, xsfMinLength, xsfMaxLength, xsfPattern, xsfEnumeration, xsfWhiteSpace,
    xsfMaxInclusive, xsfMaxExclusive, xsfMinInclusive, xsfMinExclusive,
    xsfTotalDigits, xsfFractionDigits
  );

  TLandrixXmlXsdVariety = (xsvAtomic, xsvUnion, xsvList);

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

  { An item of a list value: the fields of TLandrixXmlXsdValue for an
    atomic value. }
  TLandrixXmlXsdAtomicValue = record
    Primitive: TLandrixXmlXsdPrimitive;
    Text: TLandrixXmlUtf8;
    RawText: TLandrixXmlUtf8;
    MemberType: TLandrixXmlXsdSimpleType;
    Length: Integer;
    DecimalValue: TLandrixXmlDecimal;
    DoubleValue: TLandrixXmlDouble;
    BooleanValue: Boolean;
    DateTime: TLandrixXmlXsdDateTime;
    NamespaceUri: TLandrixXmlUtf8;
    LocalName: TLandrixXmlUtf8;
  end;

  TLandrixXmlXsdAtomicValueArray = array of TLandrixXmlXsdAtomicValue;

  { A value in the value space of a primitive type. Text is the lexical
    form after white space normalization, RawText the value as given;
    Length is the length counted by the length facets (characters as
    UTF-16 code units like Xerces, or octets for the binary types).
    MemberType is the member type of a union that accepted the value, else
    the validated type itself.
    Variety is xsvList for a value of a list type: Items holds the items
    (MemberType: the item type, or the member of a union item type that
    accepted the item), Text the whole value with collapsed white space,
    Length the number of items, Primitive is xspAnySimpleType. Otherwise
    Variety is xsvAtomic and Items is empty.
    For xspQName and xspNotation, NamespaceUri ('' for none) and LocalName
    are the resolved name; Text keeps the lexical form with the prefix.
    For xspDuration, DateTime holds the fields as written (years, months,
    days, hours, minutes, seconds), all of them negative for a negative
    duration; HasTimeZone is False. }
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
    Variety: TLandrixXmlXsdVariety;
    Items: TLandrixXmlXsdAtomicValueArray;
    NamespaceUri: TLandrixXmlUtf8;
    LocalName: TLandrixXmlUtf8;
  end;

  { A failed check: Code is the Xerces code ("cvc-pattern-valid"),
    Message an English text in the style of Xerces. }
  TLandrixXmlXsdError = record
    Code: string;
    Message: string;
  end;

  TLandrixXmlXsdSimpleTypeArray = array of TLandrixXmlXsdSimpleType;
  TLandrixXmlXsdValueArray = array of TLandrixXmlXsdValue;

  { The namespace declarations in scope where a value occurs, to resolve
    the prefixes of QName values. Prefix '' asks for the default
    namespace; False if the prefix is not declared. }
  TLandrixXmlXsdNamespaceContext = class
  public
    function LookupNamespace(const Prefix: TLandrixXmlUtf8; out NamespaceUri: TLandrixXmlUtf8): Boolean;
      virtual; abstract;
  end;

  { A bound of a range facet. }
  TLandrixXmlXsdBound = record
    Present: Boolean;
    Value: TLandrixXmlXsdValue;
  end;

  { A derivation step; as a set, the derivations a final or block forbids
    (the final, disallowed substitutions and prohibited substitutions of
    XML Schema). }
  TLandrixXmlXsdDerivation = (xdRestriction, xdExtension, xdList, xdUnion, xdSubstitution);
  TLandrixXmlXsdDerivations = set of TLandrixXmlXsdDerivation;

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
    FItemType: TLandrixXmlXsdSimpleType;
    FBuiltin: Boolean;
    FFinal: TLandrixXmlXsdDerivations;
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
    { the facets given on this type (patterns and enumeration not counted)
      and those of them that are fixed }
    FDefined: set of TLandrixXmlXsdFacet;
    FFixed: set of TLandrixXmlXsdFacet;
    procedure InitFacets;
    function BaseCount(Facet: TLandrixXmlXsdFacet): Integer;
    function BaseFixed(Facet: TLandrixXmlXsdFacet): Boolean;
    procedure BaseBounds(Upper: Boolean; out Inclusive, Exclusive: TLandrixXmlXsdBound);
    procedure CheckFixedBound(Facet: TLandrixXmlXsdFacet; const Bound, BaseBound: TLandrixXmlXsdBound);
    procedure CheckFacetConsistency;
    function CheckFacets(const Value: TLandrixXmlXsdValue; out Error: TLandrixXmlXsdError): Boolean;
    function ValidatorName: string;
    function HasPatterns: Boolean;
    function IsTrimmedType: Boolean;
    function CheckPatterns(const Value: TLandrixXmlXsdValue; const TypeName: string;
      out Error: TLandrixXmlXsdError): Boolean;
    function ParseFacetValue(const Text: TLandrixXmlUtf8; const Code: string;
      Context: TLandrixXmlXsdNamespaceContext): TLandrixXmlXsdValue;
    function ParseBound(Facet: TLandrixXmlXsdFacet; const Text: TLandrixXmlUtf8): TLandrixXmlXsdValue;
    function ValidateList(const Text: TLandrixXmlUtf8; Context: TLandrixXmlXsdNamespaceContext;
      out Value: TLandrixXmlXsdValue; out Error: TLandrixXmlXsdError; out HasValue: Boolean): Boolean;
    function GetMemberCount: Integer;
    function GetMember(Index: Integer): TLandrixXmlXsdSimpleType;
    procedure SetFinal(Value: TLandrixXmlXsdDerivations);
    function DerivedFromMember(Union: TLandrixXmlXsdSimpleType; Block: TLandrixXmlXsdDerivations): Boolean;
    function ValidateLexical(const Text: TLandrixXmlUtf8; Context: TLandrixXmlXsdNamespaceContext;
      out Value: TLandrixXmlXsdValue; out Error: TLandrixXmlXsdError): Boolean;
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
    { A list of ItemType values (the parameter order differs from
      CreateRestriction for C++ Builder). Raises ELandrixXmlError (xecInvalidArgument)
      if ItemType is a list or a union with a list member
      (cos-st-restricts.2.1). }
    constructor CreateList(const NamespaceUri, Name: TLandrixXmlUtf8; ItemType: TLandrixXmlXsdSimpleType);
    destructor Destroy; override;
    { Adds a facet as written in the schema; Fixed is its fixed attribute.
      Several patterns of the same type are alternatives. Raises
      ELandrixXmlError: xecInvalidArgument for a facet value that is
      invalid, not allowed for the base type or inconsistent with the
      facets given so far or with those of the base type (as Xerces checks
      them; the message of a failed check ends with the Xerces code in
      parentheses, e.g. "(minLength-less-than-equal-to-maxLength)");
      xecInvalidOperation on a built-in type and on a type made by
      CreateList or CreateUnion (facets of a list or union go on a
      restriction of it). A union allows pattern and enumeration. }
    procedure AddFacet(Facet: TLandrixXmlXsdFacet; const Value: TLandrixXmlUtf8; Fixed: Boolean = False);
      overload;
    { As above; Context resolves the prefixes of QName values in the facet
      value (an enumeration), nil for none. }
    procedure AddFacet(Facet: TLandrixXmlXsdFacet; const Value: TLandrixXmlUtf8;
      Context: TLandrixXmlXsdNamespaceContext; Fixed: Boolean); overload;
    { Checks Text (an element or attribute value as written) without a
      namespace context: a QName with a prefix other than xml and xmlns
      is invalid (UndeclaredPrefix), one without has no namespace. After
      a False result Value is unspecified. }
    function Validate(const Text: TLandrixXmlUtf8; out Value: TLandrixXmlXsdValue;
      out Error: TLandrixXmlXsdError): Boolean; overload;
    { Checks Text; Context resolves the prefixes of QName values (also in
      lists and unions), nil for none. After a False result Value is
      unspecified. }
    function Validate(const Text: TLandrixXmlUtf8; Context: TLandrixXmlXsdNamespaceContext;
      out Value: TLandrixXmlXsdValue; out Error: TLandrixXmlXsdError): Boolean; overload;
    { As above; HasValue tells whether Value is defined. It is True on
      success and after a failure that came after Xerces had computed a
      value, which its identity constraints then use: the value itself if
      only a facet other than pattern failed (also one of a list or of a
      restricted union), the value of the last list item that had one if
      an item failed, and the value of the last member type that had one
      if no member type of a union matched. False if the lexical form or
      a pattern failed before any value was computed. }
    function Validate(const Text: TLandrixXmlUtf8; Context: TLandrixXmlXsdNamespaceContext;
      out Value: TLandrixXmlXsdValue; out Error: TLandrixXmlXsdError; out HasValue: Boolean): Boolean;
      overload;
    property NamespaceUri: TLandrixXmlUtf8 read FNamespaceUri;
    property Name: TLandrixXmlUtf8 read FName;
    { For an anonymous type: the name messages use, as the schema loader
      gives it (Xerces' #AnonType_ followed by the names of the enclosing
      declarations). }
    property AnonymousName: TLandrixXmlUtf8 read FAnonymousName write FAnonymousName;
    property Base: TLandrixXmlXsdSimpleType read FBase;
    property Variety: TLandrixXmlXsdVariety read FVariety;
    { the item type of a list type (also of a restriction of one), else nil }
    property ItemType: TLandrixXmlXsdSimpleType read FItemType;
    property Primitive: TLandrixXmlXsdPrimitive read FPrimitive;
    property LexicalRule: TLandrixXmlXsdLexicalRule read FLexicalRule;
    property WhiteSpace: TLandrixXmlXsdWhiteSpace read FWhiteSpace;
    property Builtin: Boolean read FBuiltin;
    { The derivations the type's final forbids (its final attribute or the
      finalDefault of its schema document, as the schema loader sets it);
      empty for the built-in types, whose final cannot be set
      (ELandrixXmlError xecInvalidOperation). }
    property Final: TLandrixXmlXsdDerivations read FFinal write SetFinal;
    { The name Xerces uses for the type in messages: the name, the
      AnonymousName, or #AnonType_ and the name of the nearest named base. }
    function DisplayName: string;
    { True if AType is this type or one of its base types (to recognize ID
      and IDREF values). }
    function IsDerivedFrom(AType: TLandrixXmlXsdSimpleType): Boolean;
    { True if the type is Base or validly derived from it without the
      derivations in Block (Type Derivation OK (Simple), as Xerces'
      checkSimpleDerivationOk: also through the members of a union Base,
      and a list or union from anySimpleType). }
    function DerivationOk(Base: TLandrixXmlXsdSimpleType; Block: TLandrixXmlXsdDerivations): Boolean;
    { True if the type is xs:ID or derived from it, a list of such items or
      a union with such a member (Xerces' isIDType). }
    function IsIdType: Boolean;
    { The member types of a union (also of a restriction of one); 0 for
      the other varieties. }
    property MemberCount: Integer read GetMemberCount;
    property Members[Index: Integer]: TLandrixXmlXsdSimpleType read GetMember;
  end;

{ The built-in type with this local name in the XML Schema namespace, or
  nil if it is unknown or not supported. The types are shared; never free
  them. }
function LandrixXmlXsdBuiltinType(const LocalName: TLandrixXmlUtf8): TLandrixXmlXsdSimpleType;

{ A value as Xerces prints it in messages, its canonical form: a decimal
  with ".0" unless its type is an integer type, a boolean as true or
  false, float and double as 1.5E3 (zero as 0.0E1), dates and times with
  a time zone moved to UTC ("2025-12-31Z"), a duration with every field
  ("P1Y0M2DT0H0M0S"), hexBinary in upper case, base64Binary without white
  space, other values in their normalized lexical form. }
function LandrixXmlXsdValueText(const Value: TLandrixXmlXsdValue): TLandrixXmlUtf8;

{ A key for comparing values as Xerces does for identity constraints:
  equal keys for equal values (0 and -0, all NaNs, the same instant in
  different time zones, durations Xerces finds equal such as P1D and
  PT24H), different keys for values of different
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
          { Xerces deviation: gMonth_pattern001_1274, gMonth_enumeration002_203, gMonth_maxInclusive002_205,
            gMonth_maxExclusive002_208, gMonth_minInclusive002_210, gMonth_minExclusive002_213,
            gMonth_enumeration001_1275, gMonth_enumeration002_1276, gMonth_enumeration003_1277,
            gMonth_enumeration004_1278, gMonth_maxInclusive001_1279, gMonth_maxInclusive002_1280,
            gMonth_maxInclusive003_1281, gMonth_maxExclusive001_1282, gMonth_maxExclusive002_1283,
            gMonth_maxExclusive003_1284, gMonth_minInclusive001_1285, gMonth_minInclusive002_1286,
            gMonth_minInclusive003_1287, gMonth_minInclusive004_1288, gMonth_minInclusive005_1289,
            gMonth_minExclusive001_1290, gMonth_minExclusive002_1291, gMonth_minExclusive003_1292,
            gMonth_minExclusive004_1293, gMonth_minExclusive005_1294.
            Xerces also accepts --MM--, the form of XML Schema 1.0 before
            its errata (also in facet values) }
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
  parser uses the Fifth Edition, which allows more characters).
  Xerces deviation: xv001, xv002, xv004, xv009. }
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

{ The position of the first colon in S, 0 if there is none. }
function ColonIndex(const S: TLandrixXmlUtf8): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) do
    if S[I] = ':' then
    begin
      Result := I;
      Exit;
    end;
end;

function ParseDuration(const S: TLandrixXmlUtf8; out D: TLandrixXmlXsdDateTime): Boolean; forward;

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
  Value.NamespaceUri := '';
  Value.LocalName := '';
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
        if Primitive = xspFloat then
          Result := LandrixXmlDoubleTryParseFloat(Normalized, Value.DoubleValue)
        else
          Result := LandrixXmlDoubleTryParse(Normalized, Value.DoubleValue);
      end;
    xspDateTime, xspTime, xspDate, xspGYearMonth, xspGYear, xspGMonthDay, xspGDay, xspGMonth:
      Result := ParseDateTimeKind(Normalized, Primitive, Value.DateTime);
    xspDuration:
      Result := ParseDuration(Normalized, Value.DateTime);
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
    xspQName, xspNotation:
      begin
        { an optional prefix before the first colon (Xerces), both parts
          NCNames; the prefix is resolved by the caller }
        I := ColonIndex(Normalized);
        if I > 1 then
        begin
          if not IsNameKind(Copy(Normalized, 1, I - 1), xslNCName) then
            Exit;
          Value.LocalName := Copy(Normalized, I + 1, MaxInt);
        end
        else
          Value.LocalName := Normalized;
        Result := IsNameKind(Value.LocalName, xslNCName);
      end;
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

{ ---------------------------------------------------------------------- }
{ xs:duration (Xerces' DurationDV)                                        }
{ ---------------------------------------------------------------------- }

{ Java int arithmetic: the result wrapped to 32 bits }
function Wrap32(X: Int64): Integer;
begin
  X := X and $FFFFFFFF;
  if X >= $80000000 then
    X := X - $100000000;
  Result := Integer(X);
end;

{ Java's (float) of an int: rounded to 24 significant bits, ties to even }
function JavaFloatOfInt(A: Integer): Int64;
var
  M, Q, R, Half: Int64;
  Shift: Integer;
begin
  M := A;
  if M < 0 then
    M := -M;
  Shift := 0;
  while (M shr Shift) >= $1000000 do
    Inc(Shift);
  if Shift = 0 then
  begin
    Result := A;
    Exit;
  end;
  Q := M shr Shift;
  R := M - (Q shl Shift);
  Half := Int64(1) shl (Shift - 1);
  if (R > Half) or ((R = Half) and Odd(Q)) then
    Inc(Q);
  Result := Q shl Shift;
  if A < 0 then
    Result := -Result;
end;

{ Xerces' fQuotient(a, b): (int) Math.floor((float) a / b) with the float
  rounding of Java (B > 0) }
function JavaFloatFloorDiv(A, B: Integer): Integer;
var
  M, Num, Den, K, R, V: Int64;
  E, S: Integer;
  Negative: Boolean;
begin
  M := JavaFloatOfInt(A);
  if M = 0 then
  begin
    Result := 0;
    Exit;
  end;
  Negative := M < 0;
  if Negative then
    M := -M;
  { E: 2^E <= M / B < 2^(E + 1) }
  E := 0;
  if M >= B then
  begin
    while (Int64(B) shl (E + 1)) <= M do
      Inc(E);
  end
  else
    while (M shl (-E)) < B do
      Dec(E);
  { the quotient rounded to 24 significant bits: K * 2^(E - 23) }
  if E <= 23 then
  begin
    Num := M shl (23 - E);
    Den := B;
  end
  else
  begin
    Num := M;
    Den := Int64(B) shl (E - 23);
  end;
  K := Num div Den;
  R := Num - K * Den;
  if (2 * R > Den) or ((2 * R = Den) and Odd(K)) then
    Inc(K);
  { floor of K * 2^(E - 23), with the sign }
  if E >= 23 then
    V := K shl (E - 23)
  else
  begin
    S := 23 - E;
    if Negative then
      V := (K + (Int64(1) shl S) - 1) shr S
    else
      V := K shr S;
  end;
  if Negative then
    V := -V;
  Result := Wrap32(V);
end;

{ Xerces' modulo(temp, low, high) and fQuotient(temp, low, high) }
function XercesModulo(Temp, Low, High: Integer): Integer;
var
  A, B: Integer;
begin
  A := Wrap32(Int64(Temp) - Low);
  B := High - Low;
  Result := Wrap32(Int64(Wrap32(Int64(A) - Int64(Wrap32(Int64(JavaFloatFloorDiv(A, B)) * B)))) + Low);
end;

function XercesQuotient(Temp, Low, High: Integer): Integer;
begin
  Result := JavaFloatFloorDiv(Wrap32(Int64(Temp) - Low), High - Low);
end;

{ Xerces' mod(a, b, quotient) }
function XercesMod(A, B, Quotient: Integer): Integer;
begin
  Result := Wrap32(Int64(A) - Int64(Wrap32(Int64(Quotient) * B)));
end;

function JavaLeapYear(Year: Integer): Boolean;
begin
  Result := (Year mod 4 = 0) and ((Year mod 100 <> 0) or (Year mod 400 = 0));
end;

{ Xerces' maxDayInMonthFor: any month other than 2, 4, 6, 9 and 11 (also
  0) has 31 days }
function JavaMaxDay(Year, Month: Integer): Integer;
begin
  if (Month = 4) or (Month = 6) or (Month = 9) or (Month = 11) then
    Result := 30
  else if Month = 2 then
  begin
    if JavaLeapYear(Year) then
      Result := 29
    else
      Result := 28;
  end
  else
    Result := 31;
end;

{ Xerces' addDuration: the duration D added to the day Year-Month-01
  (time 00:00:00Z), as Xerces computes it with Java int arithmetic. A
  loop step moves one month; whole 400-year cycles (146097 days) are
  skipped at once, which gives the same result while the year cannot
  wrap around.
  Xerces deviation, not in the test suite: sums beyond the int range wrap
  around, and the quotients of fQuotient are computed as floats, so very
  large values compare wrongly (62914619 minutes exceed 1048576 hours and
  59 minutes, the same duration); XML Schema 1.0 adds exactly }
procedure AddDurationTo(const D: TLandrixXmlXsdDateTime; Year, Month: Integer; out R: TLandrixXmlXsdDateTime);
var
  Temp, Carry, MaxDay: Integer;
  Quotient: TLandrixXmlDecimal;
  Carry64: Int64;
  Sixty: TLandrixXmlDecimal;
begin
  R.HasTimeZone := True;
  R.TimeZone := 0;
  Temp := Wrap32(Int64(Month) + D.Month);
  R.Month := XercesModulo(Temp, 1, 13);
  Carry := XercesQuotient(Temp, 1, 13);
  R.Year := Wrap32(Int64(Wrap32(Int64(Year) + D.Year)) + Carry);
  { seconds: (int) Math.floor(s / 60), saturated to the int range }
  Sixty := LandrixXmlDecimalFromInt64(60);
  Quotient := LandrixXmlDecimalIntegerQuotient(D.Second, Sixty);
  if (LandrixXmlDecimalSign(D.Second) < 0) and
    (LandrixXmlDecimalCompare(LandrixXmlDecimalMultiply(Quotient, Sixty), D.Second) <> 0) then
    Quotient := LandrixXmlDecimalSubtract(Quotient, LandrixXmlDecimalFromInt64(1));
  if not LandrixXmlDecimalTryToInt64(Quotient, Carry64) then
  begin
    if LandrixXmlDecimalSign(Quotient) < 0 then
      Carry64 := -2147483647 - 1
    else
      Carry64 := 2147483647;
  end
  else if Carry64 > 2147483647 then
    Carry64 := 2147483647
  else if Carry64 < -2147483647 - 1 then
    Carry64 := -2147483647 - 1;
  Carry := Integer(Carry64);
  R.Second := LandrixXmlDecimalSubtract(D.Second, LandrixXmlDecimalFromInt64(Wrap32(Int64(Carry) * 60)));
  Temp := Wrap32(Int64(D.Minute) + Carry);
  Carry := JavaFloatFloorDiv(Temp, 60);
  R.Minute := XercesMod(Temp, 60, Carry);
  Temp := Wrap32(Int64(D.Hour) + Carry);
  Carry := JavaFloatFloorDiv(Temp, 24);
  R.Hour := XercesMod(Temp, 24, Carry);
  R.Day := Wrap32(Int64(Wrap32(Int64(1) + D.Day)) + Carry);
  while True do
  begin
    { (not where the year could wrap around: the cycle breaks there) }
    if (R.Day > 146097 + 31) and (R.Year < 2147483647 - 402) then
    begin
      R.Day := R.Day - 146097;
      R.Year := Wrap32(Int64(R.Year) + 400);
      Continue;
    end;
    if (R.Day < -146097 - 31) and (R.Year > -2147483647 + 402) then
    begin
      R.Day := R.Day + 146097;
      R.Year := Wrap32(Int64(R.Year) - 400);
      Continue;
    end;
    MaxDay := JavaMaxDay(R.Year, R.Month);
    if R.Day < 1 then
    begin
      R.Day := R.Day + JavaMaxDay(R.Year, R.Month - 1);
      Carry := -1;
    end
    else if R.Day > MaxDay then
    begin
      R.Day := R.Day - MaxDay;
      Carry := 1;
    end
    else
      Break;
    Temp := R.Month + Carry;
    R.Month := XercesModulo(Temp, 1, 13);
    R.Year := Wrap32(Int64(R.Year) + XercesQuotient(Temp, 1, 13));
  end;
end;

{ Xerces' compareOrder on the fields of two durations or added dates }
function CompareFields(const A, B: TLandrixXmlXsdDateTime): Integer;
begin
  Result := CompareInt(A.Year, B.Year);
  if Result = 0 then
    Result := CompareInt(A.Month, B.Month);
  if Result = 0 then
    Result := CompareInt(A.Day, B.Day);
  if Result = 0 then
    Result := CompareInt(A.Hour, B.Hour);
  if Result = 0 then
    Result := CompareInt(A.Minute, B.Minute);
  if Result = 0 then
    Result := LandrixXmlDecimalCompare(A.Second, B.Second);
end;

const
  { Xerces' reference dates for the order of durations (XML Schema 1.0,
    3.2.6.2) }
  DurationYears: array[0..3] of Integer = (1696, 1697, 1903, 1903);
  DurationMonths: array[0..3] of Integer = (9, 2, 3, 7);

{ Xerces' compareDates for durations (strict): equal fields, or the same
  order after adding both to each of the four reference dates; otherwise
  LandrixXmlXsdIncomparable }
function CompareDuration(const A, B: TLandrixXmlXsdDateTime): Integer;
var
  I, Order: Integer;
  RA, RB: TLandrixXmlXsdDateTime;
begin
  Result := CompareFields(A, B);
  if Result = 0 then
    Exit;
  for I := 0 to 3 do
  begin
    AddDurationTo(A, DurationYears[I], DurationMonths[I], RA);
    AddDurationTo(B, DurationYears[I], DurationMonths[I], RB);
    Order := CompareFields(RA, RB);
    if I = 0 then
      Result := Order
    else if Order <> Result then
    begin
      Result := 2;
      Exit;
    end;
  end;
end;

{ Xerces' DurationDV.parse: at least one number with its designator, in
  the order Y M D, then after T: H M S; whole numbers up to 2147483647;
  seconds as digits with one point at most, not ending with it (".5" is
  allowed), within the double range.
  Xerces deviation, not in the test suite: the whole numbers are limited
  to 2147483647 and seconds may start with the point; XML Schema 1.0
  allows any number of digits and wants one before the point }
function ParseDuration(const S: TLandrixXmlUtf8; out D: TLandrixXmlXsdDateTime): Boolean;
var
  Len, Start, Stop, EndDate, Negate, I, Dot: Integer;
  Designator: Boolean;
  Seconds: TLandrixXmlUtf8;
  Dbl: TLandrixXmlDouble;

  function IndexOf(From, Before: Integer; Ch: AnsiChar): Integer;
  var
    K: Integer;
  begin
    for K := From to Before - 1 do
      if AnsiChar(S[K]) = Ch then
      begin
        Result := K;
        Exit;
      end;
    Result := 0;
  end;

  { Xerces' parseInt: digits only (also none: the designator itself
    fails), at most 2147483647 }
  function TryInt(From, Before: Integer; out Value: Integer): Boolean;
  var
    K: Integer;
    N: Int64;
  begin
    Result := False;
    Value := 0;
    N := 0;
    K := From;
    repeat
      if (K > Len) or not (AnsiChar(S[K]) in ['0'..'9']) then
        Exit;
      N := N * 10 + (Ord(S[K]) - Ord('0'));
      if N > 2147483647 then
        Exit;
      Inc(K);
    until K >= Before;
    Value := Integer(N);
    Result := True;
  end;

begin
  Result := False;
  D.Year := 0;
  D.Month := 0;
  D.Day := 0;
  D.Hour := 0;
  D.Minute := 0;
  D.Second := LandrixXmlDecimalZero;
  D.HasTimeZone := False;
  D.TimeZone := 0;
  Len := Length(S);
  if Len = 0 then
    Exit;
  Start := 1;
  Negate := 1;
  if S[1] = '-' then
  begin
    Negate := -1;
    Start := 2;
  end;
  if (Start > Len) or (S[Start] <> 'P') then
    Exit;
  Inc(Start);
  Designator := False;
  EndDate := IndexOf(Start, Len + 1, 'T');
  if EndDate = 0 then
    EndDate := Len + 1;
  Stop := IndexOf(Start, EndDate, 'Y');
  if Stop <> 0 then
  begin
    if not TryInt(Start, Stop, D.Year) then
      Exit;
    D.Year := Negate * D.Year;
    Start := Stop + 1;
    Designator := True;
  end;
  Stop := IndexOf(Start, EndDate, 'M');
  if Stop <> 0 then
  begin
    if not TryInt(Start, Stop, D.Month) then
      Exit;
    D.Month := Negate * D.Month;
    Start := Stop + 1;
    Designator := True;
  end;
  Stop := IndexOf(Start, EndDate, 'D');
  if Stop <> 0 then
  begin
    if not TryInt(Start, Stop, D.Day) then
      Exit;
    D.Day := Negate * D.Day;
    Start := Stop + 1;
    Designator := True;
  end;
  if (EndDate = Len + 1) and (Start <> Len + 1) then
    Exit;
  if EndDate <> Len + 1 then
  begin
    { as Xerces: the character after the date part is skipped (it is the
      T unless the date part has something left, which then fails) }
    Inc(Start);
    Stop := IndexOf(Start, Len + 1, 'H');
    if Stop <> 0 then
    begin
      if not TryInt(Start, Stop, D.Hour) then
        Exit;
      D.Hour := Negate * D.Hour;
      Start := Stop + 1;
      Designator := True;
    end;
    Stop := IndexOf(Start, Len + 1, 'M');
    if Stop <> 0 then
    begin
      if not TryInt(Start, Stop, D.Minute) then
        Exit;
      D.Minute := Negate * D.Minute;
      Start := Stop + 1;
      Designator := True;
    end;
    Stop := IndexOf(Start, Len + 1, 'S');
    if Stop <> 0 then
    begin
      Dot := 0;
      for I := Start to Stop - 1 do
        if S[I] = '.' then
          Dot := I
        else if not (AnsiChar(S[I]) in ['0'..'9']) then
          Exit;
      if (Dot + 1 = Stop) or (Start = Stop) then
        Exit;
      Seconds := Copy(S, Start, Stop - Start);
      { Java's Double.parseDouble: one point at most, finite }
      if not LandrixXmlDoubleTryParse(Seconds, Dbl) or LandrixXmlDoubleIsInfinite(Dbl) then
        Exit;
      if not LandrixXmlTryParseDecimal(Seconds, D.Second) then
        Exit;
      if Negate < 0 then
        D.Second := LandrixXmlDecimalNegate(D.Second);
      Start := Stop + 1;
      Designator := True;
    end;
    { nothing after the last designator, and not ending with T }
    if (Start <> Len + 1) or (S[Start - 1] = 'T') then
      Exit;
  end;
  Result := Designator;
end;

{ Xerces' canonical form of a duration (dateToString): every field, the
  sign in front if any field is negative }
function DurationText(const D: TLandrixXmlXsdDateTime): TLandrixXmlUtf8;

  function Abs32(V: Integer): TLandrixXmlUtf8;
  begin
    if V < 0 then
      Result := LandrixXmlStringToUtf8(IntToStr(-Int64(V)))
    else
      Result := LandrixXmlStringToUtf8(IntToStr(V));
  end;

begin
  if (D.Year < 0) or (D.Month < 0) or (D.Day < 0) or (D.Hour < 0) or (D.Minute < 0) or
    (LandrixXmlDecimalSign(D.Second) < 0) then
    Result := '-P'
  else
    Result := 'P';
  Result := Result + Abs32(D.Year) + 'Y' + Abs32(D.Month) + 'M' + Abs32(D.Day) + 'DT' + Abs32(D.Hour) + 'H' +
    Abs32(D.Minute) + 'M' + LandrixXmlFormatDecimal(LandrixXmlDecimalAbs(D.Second)) + 'S';
end;

{ equal for durations Xerces finds equal: the dates of the four
  reference sums }
function DurationKey(const D: TLandrixXmlXsdDateTime): TLandrixXmlUtf8;
var
  I: Integer;
  R: TLandrixXmlXsdDateTime;
begin
  Result := '';
  for I := 0 to 3 do
  begin
    AddDurationTo(D, DurationYears[I], DurationMonths[I], R);
    Result := Result + LandrixXmlStringToUtf8(IntToStr(R.Year) + ':' + IntToStr(R.Month) + ':' +
      IntToStr(R.Day) + ':' + IntToStr(R.Hour) + ':' + IntToStr(R.Minute)) + ':' +
      LandrixXmlFormatDecimal(R.Second) + ';';
  end;
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

procedure AtomicFromValue(const Value: TLandrixXmlXsdValue; var Item: TLandrixXmlXsdAtomicValue);
begin
  Item.Primitive := Value.Primitive;
  Item.Text := Value.Text;
  Item.RawText := Value.RawText;
  Item.MemberType := Value.MemberType;
  Item.Length := Value.Length;
  Item.DecimalValue := Value.DecimalValue;
  Item.DoubleValue := Value.DoubleValue;
  Item.BooleanValue := Value.BooleanValue;
  Item.DateTime := Value.DateTime;
  Item.NamespaceUri := Value.NamespaceUri;
  Item.LocalName := Value.LocalName;
end;

function ValueOfItem(const Item: TLandrixXmlXsdAtomicValue): TLandrixXmlXsdValue;
begin
  Result.Primitive := Item.Primitive;
  Result.Text := Item.Text;
  Result.RawText := Item.RawText;
  Result.MemberType := Item.MemberType;
  Result.Length := Item.Length;
  Result.DecimalValue := Item.DecimalValue;
  Result.DoubleValue := Item.DoubleValue;
  Result.BooleanValue := Item.BooleanValue;
  Result.DateTime := Item.DateTime;
  Result.Variety := xsvAtomic;
  Result.Items := nil;
  Result.NamespaceUri := Item.NamespaceUri;
  Result.LocalName := Item.LocalName;
end;

{ The kind of a list value as Xerces compares it (ValidatedInfo
  .isComparable): "U" for a union item type, else "L" and the item
  type's primitive type, anySimpleType counting as string. }
function ListKind(const Value: TLandrixXmlXsdValue): TLandrixXmlUtf8;
var
  ItemType: TLandrixXmlXsdSimpleType;
  P: TLandrixXmlXsdPrimitive;
begin
  ItemType := nil;
  if Value.MemberType <> nil then
    ItemType := Value.MemberType.ItemType;
  if ItemType = nil then
    Result := 'L'
  else if ItemType.Variety = xsvUnion then
    Result := 'U'
  else
  begin
    P := ItemType.Primitive;
    if P = xspAnySimpleType then
      P := xspString;
    Result := 'L' + LandrixXmlStringToUtf8(IntToStr(Ord(P)));
  end;
end;

{ Lists are equal if their kinds and items are; they have no order. }
function CompareLists(const A, B: TLandrixXmlXsdValue): Integer;
var
  I: Integer;
begin
  Result := LandrixXmlXsdIncomparable;
  if (A.Variety <> xsvList) or (B.Variety <> xsvList) or (Length(A.Items) <> Length(B.Items)) or
    (ListKind(A) <> ListKind(B)) then
    Exit;
  for I := 0 to Integer(Length(A.Items)) - 1 do
  begin
    if LandrixXmlXsdCompareValues(ValueOfItem(A.Items[I]), ValueOfItem(B.Items[I])) <> 0 then
      Exit;
  end;
  Result := 0;
end;

function LandrixXmlXsdCompareValues(const A, B: TLandrixXmlXsdValue): Integer;
begin
  Result := LandrixXmlXsdIncomparable;
  if (A.Variety = xsvList) or (B.Variety = xsvList) then
  begin
    Result := CompareLists(A, B);
    Exit;
  end;
  { anySimpleType and string values compare as strings (Xerces
    ValidatedInfo.isComparable) }
  if (A.Primitive <> B.Primitive) and not ((A.Primitive in [xspAnySimpleType, xspString]) and
    (B.Primitive in [xspAnySimpleType, xspString])) then
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
    xspDuration:
      Result := CompareDuration(A.DateTime, B.DateTime);
    xspQName, xspNotation:
      if (A.NamespaceUri = B.NamespaceUri) and (A.LocalName = B.LocalName) then
        Result := 0;
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
  FDefined := [];
  FFixed := [];
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
  FItemType := Base.FItemType;
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

function ContainsList(T: TLandrixXmlXsdSimpleType): Boolean;
var
  I: Integer;
begin
  Result := T.Variety = xsvList;
  if T.Variety = xsvUnion then
    for I := 0 to Integer(Length(T.FMembers)) - 1 do
      if ContainsList(T.FMembers[I]) then
      begin
        Result := True;
        Exit;
      end;
end;

constructor TLandrixXmlXsdSimpleType.CreateList(const NamespaceUri, Name: TLandrixXmlUtf8;
  ItemType: TLandrixXmlXsdSimpleType);
begin
  inherited Create;
  InitFacets;
  if ItemType = nil then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'List item type missing');
  if ContainsList(ItemType) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument,
      'The item type of a list cannot be a list or a union with a list member (cos-st-restricts.2.1)');
  FNamespaceUri := NamespaceUri;
  FName := Name;
  FBase := LandrixXmlXsdBuiltinType('anySimpleType');
  FVariety := xsvList;
  FPrimitive := xspAnySimpleType;
  FWhiteSpace := xwsCollapse;
  FItemType := ItemType;
end;

destructor TLandrixXmlXsdSimpleType.Destroy;
begin
  FPatterns.Free;
  inherited Destroy;
end;

function TLandrixXmlXsdSimpleType.GetMemberCount: Integer;
begin
  Result := Integer(Length(FMembers));
end;

function TLandrixXmlXsdSimpleType.GetMember(Index: Integer): TLandrixXmlXsdSimpleType;
begin
  Result := FMembers[Index];
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

procedure TLandrixXmlXsdSimpleType.SetFinal(Value: TLandrixXmlXsdDerivations);
begin
  if FBuiltin then
    raise ELandrixXmlError.CreateCode(xecInvalidOperation, 'The final of a built-in type cannot be set');
  FFinal := Value;
end;

function TLandrixXmlXsdSimpleType.DerivationOk(Base: TLandrixXmlXsdSimpleType;
  Block: TLandrixXmlXsdDerivations): Boolean;
var
  AnySimple: TLandrixXmlXsdSimpleType;
begin
  Result := True;
  if Self = Base then
    Exit;
  Result := False;
  AnySimple := LandrixXmlXsdBuiltinType('anySimpleType');
  if (Self = AnySimple) or (FBase = nil) or (Base = nil) or (xdRestriction in Block) or
    (xdRestriction in FBase.FFinal) then
    Exit;
  if FBase = Base then
    Result := True
  else if (FBase <> AnySimple) and FBase.DerivationOk(Base, Block) then
    Result := True
  else if (FVariety <> xsvAtomic) and (Base = AnySimple) then
    Result := True
  else if Base.Variety = xsvUnion then
    Result := DerivedFromMember(Base, Block);
end;

{ Xerces' checkSimpleDerivation 2.2.4, with the members of nested unions }
function TLandrixXmlXsdSimpleType.DerivedFromMember(Union: TLandrixXmlXsdSimpleType;
  Block: TLandrixXmlXsdDerivations): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to Union.MemberCount - 1 do
    if Union.Members[I].Variety = xsvUnion then
    begin
      if DerivedFromMember(Union.Members[I], Block) then
        Exit;
    end
    else if DerivationOk(Union.Members[I], Block) then
      Exit;
  Result := False;
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

function TLandrixXmlXsdSimpleType.IsIdType: Boolean;
var
  I: Integer;
begin
  Result := False;
  case FVariety of
    xsvAtomic:
      Result := IsDerivedFrom(LandrixXmlXsdBuiltinType('ID'));
    xsvList:
      Result := FItemType.IsIdType;
    xsvUnion:
      for I := 0 to Integer(Length(FMembers)) - 1 do
        if FMembers[I].IsIdType then
        begin
          Result := True;
          Exit;
        end;
  end;
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

procedure InvalidFacetValue(const Text: TLandrixXmlUtf8; const Error: TLandrixXmlXsdError);
begin
  raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'Facet value ' + Quote(Text) +
    ' is not valid for the base type: ' + Error.Message + ' (' + Error.Code + ')');
end;

{ Code is the constraint code to report, '' for the code of the failed
  check of the base type. }
function TLandrixXmlXsdSimpleType.ParseFacetValue(const Text: TLandrixXmlUtf8;
  const Code: string; Context: TLandrixXmlXsdNamespaceContext): TLandrixXmlXsdValue;
var
  Error: TLandrixXmlXsdError;
begin
  { a facet value must be valid for the base type }
  if not FBase.Validate(Text, Context, Result, Error) then
  begin
    if Code <> '' then
      Error.Code := Code;
    InvalidFacetValue(Text, Error);
  end;
end;

procedure FacetError(const Code, Msg: string);
begin
  raise ELandrixXmlError.CreateCode(xecInvalidArgument, Msg + ' (' + Code + ')');
end;

{ The count facet (length, minLength, maxLength, totalDigits,
  fractionDigits) in effect for the base type, -1 if there is none. }
function TLandrixXmlXsdSimpleType.BaseCount(Facet: TLandrixXmlXsdFacet): Integer;
var
  T: TLandrixXmlXsdSimpleType;
begin
  Result := -1;
  T := FBase;
  while (T <> nil) and (Result < 0) do
  begin
    case Facet of
      xsfLength: Result := T.FLength;
      xsfMinLength: Result := T.FMinLength;
      xsfMaxLength: Result := T.FMaxLength;
      xsfTotalDigits: Result := T.FTotalDigits;
      xsfFractionDigits: Result := T.FFractionDigits;
    else
      Result := -1;
    end;
    T := T.FBase;
  end;
end;

{ True if a base type fixed the facet (fixed facets are inherited). }
function TLandrixXmlXsdSimpleType.BaseFixed(Facet: TLandrixXmlXsdFacet): Boolean;
var
  T: TLandrixXmlXsdSimpleType;
begin
  Result := False;
  T := FBase;
  while (T <> nil) and not Result do
  begin
    Result := Facet in T.FFixed;
    T := T.FBase;
  end;
end;

{ The upper (or lower) bounds in effect for the base type: as in Xerces, a
  type that gives one of the two hides both of its base types. }
procedure TLandrixXmlXsdSimpleType.BaseBounds(Upper: Boolean; out Inclusive, Exclusive: TLandrixXmlXsdBound);
var
  T: TLandrixXmlXsdSimpleType;
begin
  Inclusive.Present := False;
  Exclusive.Present := False;
  T := FBase;
  while T <> nil do
  begin
    if Upper and (T.FMaxInclusive.Present or T.FMaxExclusive.Present) then
    begin
      Inclusive := T.FMaxInclusive;
      Exclusive := T.FMaxExclusive;
      Exit;
    end;
    if not Upper and (T.FMinInclusive.Present or T.FMinExclusive.Present) then
    begin
      Inclusive := T.FMinInclusive;
      Exclusive := T.FMinExclusive;
      Exit;
    end;
    T := T.FBase;
  end;
end;

{ A bound facet value, in the order of Xerces: the lexical form for the
  base type (with its patterns), a fixed bound of the base type, then the
  other facets of the base type, except that an exclusive bound may
  repeat the one of the base type (Xerces skips that check then). }
function TLandrixXmlXsdSimpleType.ParseBound(Facet: TLandrixXmlXsdFacet;
  const Text: TLandrixXmlUtf8): TLandrixXmlXsdValue;
var
  Inclusive, Exclusive, Bound: TLandrixXmlXsdBound;
  Error: TLandrixXmlXsdError;
begin
  if not FBase.ValidateLexical(Text, nil, Result, Error) then
    InvalidFacetValue(Text, Error);
  BaseBounds(Facet in [xsfMaxInclusive, xsfMaxExclusive], Inclusive, Exclusive);
  Bound.Present := True;
  Bound.Value := Result;
  if Facet in [xsfMaxInclusive, xsfMinInclusive] then
    CheckFixedBound(Facet, Bound, Inclusive)
  else
  begin
    CheckFixedBound(Facet, Bound, Exclusive);
    if Exclusive.Present and (LandrixXmlXsdCompareValues(Result, Exclusive.Value) = 0) then
      Exit;
  end;
  { Xerces deviation: positiveInteger_maxExclusive001_1834,
    positiveInteger_maxExclusive002_1835. An exclusive bound only has to be
    a valid value of the base type, so maxExclusive 1 on positiveInteger is
    accepted, though no value is left }
  if not FBase.CheckFacets(Result, Error) then
    InvalidFacetValue(Text, Error);
end;

function FacetName(Facet: TLandrixXmlXsdFacet): string;
begin
  case Facet of
    xsfLength: Result := 'length';
    xsfMinLength: Result := 'minLength';
    xsfMaxLength: Result := 'maxLength';
    xsfPattern: Result := 'pattern';
    xsfEnumeration: Result := 'enumeration';
    xsfWhiteSpace: Result := 'whiteSpace';
    xsfMaxInclusive: Result := 'maxInclusive';
    xsfMaxExclusive: Result := 'maxExclusive';
    xsfMinInclusive: Result := 'minInclusive';
    xsfMinExclusive: Result := 'minExclusive';
    xsfTotalDigits: Result := 'totalDigits';
  else
    Result := 'fractionDigits';
  end;
end;

procedure TLandrixXmlXsdSimpleType.CheckFixedBound(Facet: TLandrixXmlXsdFacet;
  const Bound, BaseBound: TLandrixXmlXsdBound);
begin
  if Bound.Present and BaseBound.Present and BaseFixed(Facet) and
    (LandrixXmlXsdCompareValues(Bound.Value, BaseBound.Value) <> 0) then
    FacetError('FixedFacetValue', 'The ' + FacetName(Facet) + ' ' + Quote(Bound.Value.Text) +
      ' differs from the fixed value ' + Quote(BaseBound.Value.Text) + ' of the base type');
end;

function CountText(const Facet: string; Value: Integer): string;
begin
  Result := Facet + ' ''' + IntToStr(Value) + '''';
end;

{ The checks of Xerces' applyFacets between the facets of this type and
  against those of the base type, in its order. They run after each added
  facet, so a conflict is found as soon as both facets are there. }
procedure TLandrixXmlXsdSimpleType.CheckFacetConsistency;
var
  C, BaseLength, BaseMin, BaseMax, BaseTotal, BaseFraction: Integer;
begin
  { between the facets of this type }
  if (FMinLength >= 0) and (FMaxLength >= 0) and (FMinLength > FMaxLength) then
    FacetError('minLength-less-than-equal-to-maxLength', 'The ' + CountText('minLength', FMinLength) +
      ' is greater than the ' + CountText('maxLength', FMaxLength));
  if FMaxInclusive.Present and FMaxExclusive.Present then
    FacetError('maxInclusive-maxExclusive', 'maxInclusive and maxExclusive cannot both be given');
  if FMinInclusive.Present and FMinExclusive.Present then
    FacetError('minInclusive-minExclusive', 'minInclusive and minExclusive cannot both be given');
  if FMinInclusive.Present and FMaxInclusive.Present then
  begin
    C := LandrixXmlXsdCompareValues(FMinInclusive.Value, FMaxInclusive.Value);
    if (C <> -1) and (C <> 0) then
      FacetError('minInclusive-less-than-equal-to-maxInclusive', 'The minInclusive ' +
        Quote(FMinInclusive.Value.Text) + ' is not less than or equal to the maxInclusive ' +
        Quote(FMaxInclusive.Value.Text));
  end;
  if FMinExclusive.Present and FMaxExclusive.Present then
  begin
    C := LandrixXmlXsdCompareValues(FMinExclusive.Value, FMaxExclusive.Value);
    if (C <> -1) and (C <> 0) then
      FacetError('minExclusive-less-than-equal-to-maxExclusive', 'The minExclusive ' +
        Quote(FMinExclusive.Value.Text) + ' is not less than or equal to the maxExclusive ' +
        Quote(FMaxExclusive.Value.Text));
  end;
  if FMinExclusive.Present and FMaxInclusive.Present and
    (LandrixXmlXsdCompareValues(FMinExclusive.Value, FMaxInclusive.Value) <> -1) then
    FacetError('minExclusive-less-than-maxInclusive', 'The minExclusive ' + Quote(FMinExclusive.Value.Text) +
      ' is not less than the maxInclusive ' + Quote(FMaxInclusive.Value.Text));
  if FMinInclusive.Present and FMaxExclusive.Present and
    (LandrixXmlXsdCompareValues(FMinInclusive.Value, FMaxExclusive.Value) <> -1) then
    FacetError('minInclusive-less-than-maxExclusive', 'The minInclusive ' + Quote(FMinInclusive.Value.Text) +
      ' is not less than the maxExclusive ' + Quote(FMaxExclusive.Value.Text));
  if (FFractionDigits >= 0) and (FTotalDigits >= 0) and (FFractionDigits > FTotalDigits) then
    FacetError('fractionDigits-totalDigits', 'The ' + CountText('fractionDigits', FFractionDigits) +
      ' is greater than the ' + CountText('totalDigits', FTotalDigits));
  { against the base type }
  BaseLength := BaseCount(xsfLength);
  BaseMin := BaseCount(xsfMinLength);
  BaseMax := BaseCount(xsfMaxLength);
  if FLength >= 0 then
  begin
    if (BaseMin >= 0) and (FLength < BaseMin) then
      FacetError('length-minLength-maxLength.1.1', 'The ' + CountText('length', FLength) +
        ' is less than the ' + CountText('minLength', BaseMin) + ' of the base type');
    if (BaseMax >= 0) and (FLength > BaseMax) then
      FacetError('length-minLength-maxLength.2.1', 'The ' + CountText('length', FLength) +
        ' is greater than the ' + CountText('maxLength', BaseMax) + ' of the base type');
    if (BaseLength >= 0) and (FLength <> BaseLength) then
      FacetError('length-valid-restriction', 'The ' + CountText('length', FLength) +
        ' differs from the ' + CountText('length', BaseLength) + ' of the base type');
  end;
  { with a length, minLength and maxLength may only repeat the ones of the
    base type (Xerces deviation: errF001; the errata allow more) }
  if (BaseLength >= 0) or (FLength >= 0) then
  begin
    if FMinLength >= 0 then
    begin
      if (BaseLength >= 0) and (BaseLength < FMinLength) then
        FacetError('length-minLength-maxLength.1.1', 'The ' + CountText('length', BaseLength) +
          ' of the base type is less than the ' + CountText('minLength', FMinLength));
      if (FLength >= 0) and (FLength < FMinLength) then
        FacetError('length-minLength-maxLength.1.1', 'The ' + CountText('length', FLength) +
          ' is less than the ' + CountText('minLength', FMinLength));
      if BaseMin < 0 then
        FacetError('length-minLength-maxLength.1.2.a', 'minLength cannot be given with length unless the ' +
          'base type has a minLength');
      if FMinLength <> BaseMin then
        FacetError('length-minLength-maxLength.1.2.b', 'The ' + CountText('minLength', FMinLength) +
          ' given with length differs from the ' + CountText('minLength', BaseMin) + ' of the base type');
    end;
    if FMaxLength >= 0 then
    begin
      if (BaseLength >= 0) and (BaseLength > FMaxLength) then
        FacetError('length-minLength-maxLength.2.1', 'The ' + CountText('length', BaseLength) +
          ' of the base type is greater than the ' + CountText('maxLength', FMaxLength));
      if (FLength >= 0) and (FLength > FMaxLength) then
        FacetError('length-minLength-maxLength.2.1', 'The ' + CountText('length', FLength) +
          ' is greater than the ' + CountText('maxLength', FMaxLength));
      if BaseMax < 0 then
        FacetError('length-minLength-maxLength.2.2.a', 'maxLength cannot be given with length unless the ' +
          'base type has a maxLength');
      if FMaxLength <> BaseMax then
        FacetError('length-minLength-maxLength.2.2.b', 'The ' + CountText('maxLength', FMaxLength) +
          ' given with length differs from the ' + CountText('maxLength', BaseMax) + ' of the base type');
    end;
  end;
  if FMinLength >= 0 then
  begin
    { as Xerces: against the base minLength only without a base maxLength }
    if BaseMax >= 0 then
    begin
      if FMinLength > BaseMax then
        FacetError('minLength-less-than-equal-to-maxLength', 'The ' + CountText('minLength', FMinLength) +
          ' is greater than the ' + CountText('maxLength', BaseMax) + ' of the base type');
    end
    else if BaseMin >= 0 then
    begin
      if BaseFixed(xsfMinLength) and (FMinLength <> BaseMin) then
        FacetError('FixedFacetValue', 'The ' + CountText('minLength', FMinLength) +
          ' differs from the fixed value ''' + IntToStr(BaseMin) + ''' of the base type');
      if FMinLength < BaseMin then
        FacetError('minLength-valid-restriction', 'The ' + CountText('minLength', FMinLength) +
          ' is less than the ' + CountText('minLength', BaseMin) + ' of the base type');
    end;
  end;
  if (FMaxLength >= 0) and (BaseMin >= 0) and (FMaxLength < BaseMin) then
    FacetError('minLength-less-than-equal-to-maxLength', 'The ' + CountText('maxLength', FMaxLength) +
      ' is less than the ' + CountText('minLength', BaseMin) + ' of the base type');
  if (FMaxLength >= 0) and (BaseMax >= 0) then
  begin
    if BaseFixed(xsfMaxLength) and (FMaxLength <> BaseMax) then
      FacetError('FixedFacetValue', 'The ' + CountText('maxLength', FMaxLength) +
        ' differs from the fixed value ''' + IntToStr(BaseMax) + ''' of the base type');
    if FMaxLength > BaseMax then
      FacetError('maxLength-valid-restriction', 'The ' + CountText('maxLength', FMaxLength) +
        ' is greater than the ' + CountText('maxLength', BaseMax) + ' of the base type');
  end;
  { the bounds against the base type: in ParseBound }
  BaseTotal := BaseCount(xsfTotalDigits);
  BaseFraction := BaseCount(xsfFractionDigits);
  if (FTotalDigits >= 0) and (BaseTotal >= 0) then
  begin
    if BaseFixed(xsfTotalDigits) and (FTotalDigits <> BaseTotal) then
      FacetError('FixedFacetValue', 'The ' + CountText('totalDigits', FTotalDigits) +
        ' differs from the fixed value ''' + IntToStr(BaseTotal) + ''' of the base type');
    if FTotalDigits > BaseTotal then
      FacetError('totalDigits-valid-restriction', 'The ' + CountText('totalDigits', FTotalDigits) +
        ' is greater than the ' + CountText('totalDigits', BaseTotal) + ' of the base type');
  end;
  if (FFractionDigits >= 0) and (BaseTotal >= 0) and (FFractionDigits > BaseTotal) then
    FacetError('fractionDigits-totalDigits', 'The ' + CountText('fractionDigits', FFractionDigits) +
      ' is greater than the ' + CountText('totalDigits', BaseTotal) + ' of the base type');
  if FFractionDigits >= 0 then
  begin
    { xs:integer and the types derived from it have fractionDigits 0, fixed }
    if (FLexicalRule = xslInteger) and (FFractionDigits <> 0) then
      FacetError('FixedFacetValue', 'The ' + CountText('fractionDigits', FFractionDigits) +
        ' differs from the fixed value ''0'' of the base type');
    if BaseFraction >= 0 then
    begin
      if BaseFixed(xsfFractionDigits) and (FFractionDigits <> BaseFraction) then
        FacetError('FixedFacetValue', 'The ' + CountText('fractionDigits', FFractionDigits) +
          ' differs from the fixed value ''' + IntToStr(BaseFraction) + ''' of the base type');
      if FFractionDigits > BaseFraction then
        FacetError('fractionDigits-valid-restriction', 'The ' + CountText('fractionDigits', FFractionDigits) +
          ' is greater than the ' + CountText('fractionDigits', BaseFraction) + ' of the base type');
    end;
  end;
end;

{ XML Schema 1.0 Part 2, 4.1.5 (cos-applicable-facets) }
function FacetApplies(Primitive: TLandrixXmlXsdPrimitive; Facet: TLandrixXmlXsdFacet): Boolean;
begin
  case Primitive of
    { as Xerces: not even whiteSpace on anySimpleType itself (the facets
      of a list are checked by the caller) }
    xspAnySimpleType:
      Result := False;
    xspString, xspHexBinary, xspBase64Binary, xspAnyURI, xspQName, xspNotation:
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

procedure TLandrixXmlXsdSimpleType.AddFacet(Facet: TLandrixXmlXsdFacet; const Value: TLandrixXmlUtf8;
  Fixed: Boolean);
begin
  AddFacet(Facet, Value, nil, Fixed);
end;

procedure TLandrixXmlXsdSimpleType.AddFacet(Facet: TLandrixXmlXsdFacet; const Value: TLandrixXmlUtf8;
  Context: TLandrixXmlXsdNamespaceContext; Fixed: Boolean);
var
  V: TLandrixXmlXsdValue;
  Mode: TLandrixXmlXsdWhiteSpace;
  T: TLandrixXmlXsdSimpleType;
begin
  if FBuiltin then
    raise ELandrixXmlError.CreateCode(xecInvalidOperation, 'Built-in types cannot get facets');
  { the facets of a list belong to a restriction of it (its values are
    lists, the list type itself derives from anySimpleType) }
  if (FVariety = xsvList) and (FBase.FVariety <> xsvList) then
    raise ELandrixXmlError.CreateCode(xecInvalidOperation, 'Facets of a list type go on a restriction of it');
  if (FVariety = xsvUnion) and (FBase.FVariety <> xsvUnion) then
    raise ELandrixXmlError.CreateCode(xecInvalidOperation, 'Facets of a union type go on a restriction of it');
  if (FVariety = xsvList) and not (Facet in [xsfLength, xsfMinLength, xsfMaxLength, xsfPattern,
    xsfEnumeration, xsfWhiteSpace]) or (FVariety = xsvUnion) and not (Facet in [xsfPattern, xsfEnumeration]) or
    (FVariety = xsvAtomic) and not FacetApplies(FPrimitive, Facet) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument,
      'Facet not allowed for this type (cos-applicable-facets)');
  if Facet in FDefined then
    FacetError('src-single-facet-value', 'The facet ' + FacetName(Facet) + ' is given twice');
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
        V := ParseFacetValue(Value, 'enumeration-valid-restriction', Context);
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
        { the built-in types other than string and its derivations fix
          collapse, so do lists }
        if ((FVariety = xsvList) or (FPrimitive <> xspString) and (FPrimitive <> xspAnySimpleType)) and
          (Mode <> xwsCollapse) then
          FacetError('FixedFacetValue', 'whiteSpace must be collapse for this type');
        T := FBase;
        while (T <> nil) and not (xsfWhiteSpace in T.FFixed) do
          T := T.FBase;
        if (T <> nil) and (Mode <> FBase.FWhiteSpace) then
          FacetError('FixedFacetValue', 'whiteSpace differs from the fixed value of the base type');
        if (Mode = xwsPreserve) and (FBase.FWhiteSpace = xwsReplace) then
          FacetError('whiteSpace-valid-restriction.2', 'whiteSpace cannot be weaker than the base type''s');
        if Mode < FBase.FWhiteSpace then
          FacetError('whiteSpace-valid-restriction.1', 'whiteSpace cannot be weaker than the base type''s');
        FWhiteSpace := Mode;
      end;
    xsfMaxInclusive:
      begin
        FMaxInclusive.Value := ParseBound(Facet, Value);
        FMaxInclusive.Present := True;
      end;
    xsfMaxExclusive:
      begin
        FMaxExclusive.Value := ParseBound(Facet, Value);
        FMaxExclusive.Present := True;
      end;
    xsfMinInclusive:
      begin
        FMinInclusive.Value := ParseBound(Facet, Value);
        FMinInclusive.Present := True;
      end;
    xsfMinExclusive:
      begin
        FMinExclusive.Value := ParseBound(Facet, Value);
        FMinExclusive.Present := True;
      end;
  end;
  if not (Facet in [xsfPattern, xsfEnumeration]) then
  begin
    Include(FDefined, Facet);
    if Fixed then
      Include(FFixed, Facet);
  end;
  CheckFacetConsistency;
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
  moved to UTC the way Xerces' normalize does it.
  Xerces deviation, not in the test suite: so xs:time 24:00:00 is
  00:00:00 of the day after the placeholder, unequal to 00:00:00 and
  after 23:59:59, where XML Schema 1.0 makes it the same time of day as
  00:00:00. }
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
    if IsFloat then
      Back := LandrixXmlDoubleParseFloat(T)
    else
      Back := LandrixXmlDoubleParse(T);
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
    xspDuration:
      Result := DurationText(Value.DateTime);
    xspHexBinary:
      Result := AsciiUpper(Value.Text);
    xspBase64Binary:
      Result := WithoutWhiteSpace(Value.Text);
  else
    Result := Value.Text;
  end;
end;

function LandrixXmlXsdValueText(const Value: TLandrixXmlXsdValue): TLandrixXmlUtf8;
var
  I: Integer;
begin
  if Value.Variety = xsvList then
  begin
    { the items' canonical forms, separated by spaces }
    Result := '';
    for I := 0 to Integer(Length(Value.Items)) - 1 do
    begin
      if I > 0 then
        Result := Result + ' ';
      Result := Result + LandrixXmlXsdValueText(ValueOfItem(Value.Items[I]));
    end;
    Exit;
  end;
  Result := ValueTextAs(Value, (Value.MemberType <> nil) and (Value.MemberType.LexicalRule = xslInteger));
end;

function LandrixXmlXsdValueKey(const Value: TLandrixXmlXsdValue): TLandrixXmlUtf8;
var
  P: TLandrixXmlXsdPrimitive;
  D: TLandrixXmlXsdDateTime;
  I: Integer;
  K: TLandrixXmlUtf8;
  ItemType: TLandrixXmlXsdSimpleType;
begin
  if Value.Variety = xsvList then
  begin
    { as Xerces: a list of a union item type ("U") never equals a list of
      an atomic item type ("L" and the item type's primitive type, which
      counts also for an empty list); then the number of items and each
      item's key with its length }
    ItemType := nil;
    if Value.MemberType <> nil then
      ItemType := Value.MemberType.ItemType;
    if (ItemType <> nil) and (ItemType.Variety = xsvUnion) then
      Result := 'U'
    else if ItemType <> nil then
      Result := 'L' + LandrixXmlStringToUtf8(IntToStr(Ord(ItemType.Primitive))) + '/'
    else
      Result := 'L/';
    Result := Result + LandrixXmlStringToUtf8(IntToStr(Integer(Length(Value.Items))));
    for I := 0 to Integer(Length(Value.Items)) - 1 do
    begin
      K := LandrixXmlXsdValueKey(ValueOfItem(Value.Items[I]));
      Result := Result + ':' + LandrixXmlStringToUtf8(IntToStr(Integer(Length(K)))) + ':' + K;
    end;
    Exit;
  end;
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
    xspDuration:
      Result := DurationKey(Value.DateTime);
    xspBoolean, xspHexBinary, xspBase64Binary:
      Result := ValueTextAs(Value, False);
    xspQName, xspNotation:
      Result := LandrixXmlStringToUtf8(IntToStr(Integer(Length(Value.NamespaceUri)))) + ':' +
        Value.NamespaceUri + Value.LocalName;
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
  T, Start: TLandrixXmlXsdSimpleType;
  I, C, Digits: Integer;
  Found: Boolean;
  TypeName: string;
begin
  Result := False;
  TypeName := DisplayName;
  { Xerces checks no length facets for QName and NOTATION values }
  if (Value.Variety <> xsvList) and (Value.Primitive in [xspQName, xspNotation]) then
    T := nil
  else
    T := Self;
  { maxLength }
  Start := T;
  while (T <> nil) and (T.FMaxLength < 0) do
    T := T.FBase;
  if (T <> nil) and (Value.Length > T.FMaxLength) then
  begin
    SetError(Error, 'cvc-maxLength-valid', LengthMessage(Value, 'maxLength', T.FMaxLength, TypeName));
    Exit;
  end;
  { minLength }
  T := Start;
  while (T <> nil) and (T.FMinLength < 0) do
    T := T.FBase;
  if (T <> nil) and (Value.Length < T.FMinLength) then
  begin
    SetError(Error, 'cvc-minLength-valid', LengthMessage(Value, 'minLength', T.FMinLength, TypeName));
    Exit;
  end;
  { length }
  T := Start;
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
  { the bounds of the most derived type that has an upper (lower) one:
    Xerces inherits maxInclusive and maxExclusive only into a type that
    has neither of them }
  { maxInclusive }
  T := Self;
  while (T <> nil) and not T.FMaxInclusive.Present and not T.FMaxExclusive.Present do
    T := T.FBase;
  if (T <> nil) and T.FMaxInclusive.Present then
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
  while (T <> nil) and not T.FMaxInclusive.Present and not T.FMaxExclusive.Present do
    T := T.FBase;
  if (T <> nil) and T.FMaxExclusive.Present and (LandrixXmlXsdCompareValues(Value, T.FMaxExclusive.Value) <> -1) then
  begin
    SetError(Error, 'cvc-maxExclusive-valid', BoundMessage(Value, 'maxExclusive', T.FMaxExclusive, T, TypeName));
    Exit;
  end;
  { minInclusive }
  T := Self;
  while (T <> nil) and not T.FMinInclusive.Present and not T.FMinExclusive.Present do
    T := T.FBase;
  if (T <> nil) and T.FMinInclusive.Present then
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
  while (T <> nil) and not T.FMinInclusive.Present and not T.FMinExclusive.Present do
    T := T.FBase;
  if (T <> nil) and T.FMinExclusive.Present and (LandrixXmlXsdCompareValues(Value, T.FMinExclusive.Value) <> 1) then
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
  EntityTypeCache: TLandrixXmlXsdSimpleType = nil;

function TLandrixXmlXsdSimpleType.IsTrimmedType: Boolean;
begin
  if FPrimitive = xspString then
    Result := ((IdTypeCache <> nil) and IsDerivedFrom(IdTypeCache)) or
      ((IdRefTypeCache <> nil) and IsDerivedFrom(IdRefTypeCache)) or
      ((EntityTypeCache <> nil) and IsDerivedFrom(EntityTypeCache))
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
  { Xerces checks NOTATION values with its QName validator }
  if T.FPrimitive = xspNotation then
    Result := 'QName'
  else if T.FLexicalRule = xslInteger then
    Result := 'integer'
  else if T.FLexicalRule = xslNCName then
    Result := 'NCName'
  else
    Result := LandrixXmlUtf8ToString(T.FName);
end;

{ As Xerces: the patterns on the whole value, each item, then the facets
  of the list. Items alternate between two records, so the value of the
  item before a failed one is still at hand (see HasValue at Validate). }
function TLandrixXmlXsdSimpleType.ValidateList(const Text: TLandrixXmlUtf8;
  Context: TLandrixXmlXsdNamespaceContext; out Value: TLandrixXmlXsdValue; out Error: TLandrixXmlXsdError;
  out HasValue: Boolean): Boolean;
var
  Normalized, Token: TLandrixXmlUtf8;
  T: TLandrixXmlXsdSimpleType;
  Items: array[0..1] of TLandrixXmlXsdValue;
  I, Start, Count, K: Integer;
  TypeName: string;
  ItemHasValue: Boolean;
begin
  Result := False;
  HasValue := False;
  Normalized := LandrixXmlXsdNormalizeWhiteSpace(Text, xwsCollapse);
  TypeName := DisplayName;
  Value.Primitive := xspAnySimpleType;
  Value.Text := Normalized;
  Value.RawText := Text;
  Value.MemberType := Self;
  Value.Length := 0;
  Value.Variety := xsvList;
  Value.Items := nil;
  Value.NamespaceUri := '';
  Value.LocalName := '';
  T := Self;
  while T <> nil do
  begin
    if not T.CheckPatterns(Value, TypeName, Error) then
      Exit;
    T := T.FBase;
  end;
  Count := 0;
  K := 0;
  I := 1;
  while I <= Length(Normalized) do
  begin
    Start := I;
    while (I <= Length(Normalized)) and (Normalized[I] <> ' ') do
      Inc(I);
    Token := Copy(Normalized, Start, I - Start);
    Inc(I);
    if not FItemType.Validate(Token, Context, Items[K], Error, ItemHasValue) then
    begin
      if ItemHasValue then
      begin
        Value := Items[K];
        HasValue := True;
      end
      else if Count > 0 then
      begin
        Value := Items[1 - K];
        HasValue := True;
      end;
      Exit;
    end;
    if Count = Length(Value.Items) then
      SetLength(Value.Items, 2 * Count + 4);
    AtomicFromValue(Items[K], Value.Items[Count]);
    Inc(Count);
    K := 1 - K;
  end;
  SetLength(Value.Items, Count);
  Value.Length := Count;
  HasValue := True;
  Result := CheckFacets(Value, Error);
end;

function TLandrixXmlXsdSimpleType.Validate(const Text: TLandrixXmlUtf8; out Value: TLandrixXmlXsdValue;
  out Error: TLandrixXmlXsdError): Boolean;
begin
  Result := Validate(Text, nil, Value, Error);
end;

function TLandrixXmlXsdSimpleType.Validate(const Text: TLandrixXmlUtf8; Context: TLandrixXmlXsdNamespaceContext;
  out Value: TLandrixXmlXsdValue; out Error: TLandrixXmlXsdError): Boolean;
var
  HasValue: Boolean;
begin
  Result := Validate(Text, Context, Value, Error, HasValue);
end;

{ HasValue follows Xerces' ValidatedInfo, whose actual value is set
  whenever a lexical stage succeeds (an atomic value, a whole list) and
  kept when a later check fails; a failed list item or union member
  leaves the last one set.
  Xerces deviation, not in the test suite: XML Schema gives an invalid
  value no actual value, so identity constraints would not see it. }
function TLandrixXmlXsdSimpleType.Validate(const Text: TLandrixXmlUtf8; Context: TLandrixXmlXsdNamespaceContext;
  out Value: TLandrixXmlXsdValue; out Error: TLandrixXmlXsdError; out HasValue: Boolean): Boolean;
var
  I: Integer;
  MemberError: TLandrixXmlXsdError;
  T: TLandrixXmlXsdSimpleType;
  Last: TLandrixXmlXsdValue;
  MemberHasValue: Boolean;
begin
  Result := False;
  HasValue := False;
  Error.Code := '';
  Error.Message := '';
  Value.Variety := xsvAtomic;
  Value.Items := nil;
  if FVariety = xsvList then
  begin
    Result := ValidateList(Text, Context, Value, Error, HasValue);
    Exit;
  end;
  if FVariety = xsvUnion then
  begin
    { as Xerces: the patterns of a restriction on the collapsed value,
      then the member types, then the enumeration }
    if HasPatterns then
    begin
      Value.Primitive := xspAnySimpleType;
      Value.Text := LandrixXmlXsdNormalizeWhiteSpace(Text, xwsCollapse);
      Value.RawText := Text;
      Value.MemberType := nil;
      Value.Length := 0;
      Value.NamespaceUri := '';
      Value.LocalName := '';
      T := Self;
      while T <> nil do
      begin
        if not T.CheckPatterns(Value, DisplayName, Error) then
          Exit;
        T := T.FBase;
      end;
    end;
    for I := 0 to Integer(Length(FMembers)) - 1 do
    begin
      if FMembers[I].Validate(Text, Context, Value, MemberError, MemberHasValue) then
      begin
        HasValue := True;
        Result := CheckFacets(Value, Error);
        Exit;
      end;
      if MemberHasValue then
      begin
        Last := Value;
        HasValue := True;
      end;
    end;
    if HasValue then
      Value := Last
    else
    begin
      Value.RawText := Text;
      Value.MemberType := nil;
    end;
    SetError(Error, 'cvc-datatype-valid.1.2.3', Quote(Text) + ' is not a valid value of union type ''' +
      DisplayName + '''.');
    Exit;
  end;
  HasValue := ValidateLexical(Text, Context, Value, Error);
  Result := HasValue and CheckFacets(Value, Error);
end;

{ An atomic value up to the facets other than patterns: white space, the
  patterns of all types and the lexical form (Xerces' getActualValue). }
function TLandrixXmlXsdSimpleType.ValidateLexical(const Text: TLandrixXmlUtf8;
  Context: TLandrixXmlXsdNamespaceContext; out Value: TLandrixXmlXsdValue; out Error: TLandrixXmlXsdError): Boolean;
var
  Normalized, Prefix, Uri: TLandrixXmlUtf8;
  Colon: Integer;
  T: TLandrixXmlXsdSimpleType;
  TypeName: string;
  Found: Boolean;
begin
  Result := False;
  Error.Code := '';
  Error.Message := '';
  Value.Variety := xsvAtomic;
  Value.Items := nil;
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
  Value.NamespaceUri := '';
  Value.LocalName := '';
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
  if FPrimitive in [xspQName, xspNotation] then
  begin
    { the prefix in the namespace context; none: the default namespace }
    Colon := ColonIndex(Normalized);
    if Colon > 1 then
      Prefix := Copy(Normalized, 1, Colon - 1)
    else
      Prefix := '';
    if (Context = nil) or not Context.LookupNamespace(Prefix, Uri) then
    begin
      { xml and xmlns are always bound (Namespaces in XML 1.0, section 3).
        Xerces deviation: QName009_2092. So xmlns:xsi is a valid QName,
        though no declaration can bind the prefix xmlns }
      if Prefix = 'xml' then
        Uri := LandrixXmlNamespaceXml
      else if Prefix = 'xmlns' then
        Uri := LandrixXmlNamespaceXmlns
      else if Prefix <> '' then
      begin
        SetError(Error, 'UndeclaredPrefix', 'Cannot resolve ' + Quote(Normalized) +
          ' as a QName: the prefix ' + Quote(Prefix) + ' is not declared.');
        Exit;
      end
      else
        Uri := '';
    end;
    Value.NamespaceUri := Uri;
  end;
  Result := True;
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

{ A built-in list type: at least one item. }
procedure AddList(const Name, ItemName: TLandrixXmlUtf8);
var
  T: TLandrixXmlXsdSimpleType;
begin
  T := TLandrixXmlXsdSimpleType.CreateList(LandrixXmlXsdNamespace, Name, Find(ItemName));
  T.FBuiltin := True;
  T.FMinLength := 1;
  BuiltinTypes.Add(T);
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
  Add('ENTITY', 'NCName', xspString, xwsCollapse, xslNCName);
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
  Add('QName', 'anySimpleType', xspQName, xwsCollapse, xslNone);
  Add('NOTATION', 'anySimpleType', xspNotation, xwsCollapse, xslNone);
  Add('gYearMonth', 'anySimpleType', xspGYearMonth, xwsCollapse, xslNone);
  Add('gYear', 'anySimpleType', xspGYear, xwsCollapse, xslNone);
  Add('gMonthDay', 'anySimpleType', xspGMonthDay, xwsCollapse, xslNone);
  Add('gDay', 'anySimpleType', xspGDay, xwsCollapse, xslNone);
  Add('gMonth', 'anySimpleType', xspGMonth, xwsCollapse, xslNone);
  Add('duration', 'anySimpleType', xspDuration, xwsCollapse, xslNone);
  Add('hexBinary', 'anySimpleType', xspHexBinary, xwsCollapse, xslNone);
  Add('base64Binary', 'anySimpleType', xspBase64Binary, xwsCollapse, xslNone);
  Add('anyURI', 'anySimpleType', xspAnyURI, xwsCollapse, xslNone);
  AddList('NMTOKENS', 'NMTOKEN');
  AddList('IDREFS', 'IDREF');
  AddList('ENTITIES', 'ENTITY');
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
  EntityTypeCache := Find('ENTITY');

finalization
  BuiltinTypes.Free;

end.
