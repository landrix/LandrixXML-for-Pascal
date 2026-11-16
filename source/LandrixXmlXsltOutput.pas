{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Internal unit of the XSLT processor (LandrixXmlXslt), not part of the
  documented API: the output properties of xsl:output and the
  serialization of a result tree as Saxon HE writes it.

  Methods xml, html, xhtml and text. xml escapes as Saxon does (& < > in text,
  also " and white space other than the space in attributes, carriage
  returns everywhere as character references) and writes the namespace
  declarations each element holds, ordered by prefix; indent="yes"
  indents as Saxon's indenter does, byte for byte (see
  TSerializer.Element). html writes HTML5 as Saxon's HTML emitter and
  HTML indenter do (see THtmlSerializer); xhtml as its XHTML
  serializer does (XML syntax, the HTML indentation). Encodings UTF-8, US-ASCII and
  ISO-8859-1: a character the encoding does not have is a hexadecimal
  character reference in text and attribute values and SERE0008 elsewhere,
  as in Saxon; another encoding raises xecUnsupported. }

unit LandrixXmlXsltOutput;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlXPathTree;

type
  TXsltCardinalArray = array of Cardinal;

  TXsltOutputProperties = class
  private
    FNames: TLandrixXmlUtf8Array;
    FValues: TLandrixXmlUtf8Array;
  public
    { the character map (xsl:character-map, use-character-maps): the
      characters and the strings written for them in text and attribute
      values, in the order added }
    MapChars: TXsltCardinalArray;
    MapStrings: TLandrixXmlUtf8Array;
    procedure SetValue(const Name, AValue: TLandrixXmlUtf8);
    { maps Code to S (replacing an earlier mapping of Code) }
    procedure AddMapping(Code: Cardinal; const S: TLandrixXmlUtf8);
    procedure AddMappings(Source: TXsltOutputProperties);
    { adds Clark names (separated by spaces) to cdata-section-elements (the
      union of every definition) }
    procedure AddCDataElements(const Names: TLandrixXmlUtf8);
    function Value(const Name, Default: TLandrixXmlUtf8): TLandrixXmlUtf8;
    function Has(const Name: TLandrixXmlUtf8): Boolean;
    function Clone: TXsltOutputProperties;
  end;

  TXsltOutputStatus = (xosSupported, xosUnsupported, xosUnknown, xosInvalid);

{ Whether an output property (an attribute of xsl:output, no namespace;
  AValue; true, 1, false, 0 and surrounding white space allowed for yes
  and no as in Saxon) is one this serializer does:
  unknown for a name XSLT 2.0 does not define, unsupported for one it does
  not do (other methods and encodings, doctype and so on, the XSLT 3.0
  properties; use-character-maps as a value: the compiler composes the
  maps into MapChars and MapStrings). }
function XsltOutputPropertyStatus(const Name, AValue: TLandrixXmlUtf8): TXsltOutputStatus;

{ Writes Tree (a document) to Stream; ForceUtf8: UTF-8 whatever the
  encoding property says (the declaration then names UTF-8). }
procedure XsltSerialize(Tree: TLandrixXmlXPathTree; Props: TXsltOutputProperties; Stream: TStream;
  ForceUtf8: Boolean);

implementation

uses
  LandrixXmlXPath,
  LandrixXmlNormalize;

{ the value of a yes/no output property (and standalone) as Saxon reads
  it: white space trimmed, true and 1 for yes, false and 0 for no }
{ the highest code point the output encoding Name has (case ignored):
  UTF-8, US-ASCII (ASCII) and ISO-8859-1 (latin1), white space around it
  allowed; 0 for another }
function EncodingMaxChar(const Name: TLandrixXmlUtf8): Cardinal;
var
  S: string;
begin
  S := LowerCase(Trim(LandrixXmlUtf8ToString(Name)));
  if (S = 'utf-8') or (S = 'utf8') then
    Result := $10FFFF
  else if (S = 'us-ascii') or (S = 'ascii') then
    Result := $7F
  else if (S = 'iso-8859-1') or (S = 'latin1') then
    Result := $FF
  else
    Result := 0;
end;

function YesNoValue(const Name, Value: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  A, B: Integer;
begin
  Result := Value;
  if (Name <> 'indent') and (Name <> 'omit-xml-declaration') and (Name <> 'byte-order-mark') and
    (Name <> 'escape-uri-attributes') and (Name <> 'include-content-type') and
    (Name <> 'undeclare-prefixes') and (Name <> 'standalone') then
    Exit;
  A := 1;
  B := Length(Value);
  while (A <= B) and (Value[A] in [#9, #10, #13, ' ']) do
    Inc(A);
  while (B >= A) and (Value[B] in [#9, #10, #13, ' ']) do
    Dec(B);
  Result := Copy(Value, A, B - A + 1);
  if (Result = 'true') or (Result = '1') then
    Result := 'yes'
  else if (Result = 'false') or (Result = '0') then
    Result := 'no';
end;

function XsltOutputPropertyStatus(const Name, AValue: TLandrixXmlUtf8): TXsltOutputStatus;
var
  Value: TLandrixXmlUtf8;
begin
  Value := YesNoValue(Name, AValue);
  Result := xosSupported;
  if (Name = 'method') or (Name = 'version') or (Name = 'encoding') or (Name = 'omit-xml-declaration') or
    (Name = 'standalone') or (Name = 'doctype-public') or (Name = 'doctype-system') or
    (Name = 'cdata-section-elements') or (Name = 'indent') or (Name = 'media-type') or
    (Name = 'byte-order-mark') or (Name = 'escape-uri-attributes') or (Name = 'include-content-type') or
    (Name = 'normalization-form') or (Name = 'undeclare-prefixes') or (Name = 'use-character-maps') or
    (Name = 'name') then
  begin
    if ((Name = 'indent') or (Name = 'omit-xml-declaration') or (Name = 'byte-order-mark') or
      (Name = 'escape-uri-attributes') or (Name = 'include-content-type') or (Name = 'undeclare-prefixes')) and
      (Value <> 'yes') and (Value <> 'no') or (Name = 'standalone') and (Value <> 'yes') and (Value <> 'no') and
      (Value <> 'omit') then
      Result := xosInvalid
    else if (Name = 'name') or (Name = 'use-character-maps') or (Name = 'doctype-public') or
      (Name = 'doctype-system') or (Name = 'method') and (Value <> 'xml') and
      (Value <> 'text') and (Value <> 'html') and (Value <> 'xhtml') or (Name = 'encoding') and
      (EncodingMaxChar(Value) = 0) or
      (Name = 'byte-order-mark') and (Value = 'yes') or (Name = 'normalization-form') and (Value <> 'none') then
      Result := xosUnsupported;
  end
  else if (Name = 'item-separator') or (Name = 'html-version') or (Name = 'suppress-indentation') or
    (Name = 'build-tree') or (Name = 'parameter-document') or (Name = 'json-node-output-method') or
    (Name = 'allow-duplicate-names') then
    Result := xosUnsupported
  else
    Result := xosUnknown;
end;

{ --- TXsltOutputProperties ------------------------------------------------- }

procedure TXsltOutputProperties.SetValue(const Name, AValue: TLandrixXmlUtf8);
var
  I: Integer;
  V: TLandrixXmlUtf8;
begin
  V := YesNoValue(Name, AValue);
  for I := 0 to Integer(Length(FNames)) - 1 do
    if FNames[I] = Name then
    begin
      FValues[I] := V;
      Exit;
    end;
  I := Integer(Length(FNames));
  SetLength(FNames, I + 1);
  SetLength(FValues, I + 1);
  FNames[I] := Name;
  FValues[I] := V;
end;

function TXsltOutputProperties.Value(const Name, Default: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  for I := 0 to Integer(Length(FNames)) - 1 do
    if FNames[I] = Name then
    begin
      Result := FValues[I];
      Exit;
    end;
  Result := Default;
end;

function TXsltOutputProperties.Has(const Name: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to Integer(Length(FNames)) - 1 do
    if FNames[I] = Name then
      Exit;
  Result := False;
end;

function TXsltOutputProperties.Clone: TXsltOutputProperties;
begin
  Result := TXsltOutputProperties.Create;
  Result.FNames := Copy(FNames, 0, Length(FNames));
  Result.FValues := Copy(FValues, 0, Length(FValues));
  Result.MapChars := Copy(MapChars, 0, Length(MapChars));
  Result.MapStrings := Copy(MapStrings, 0, Length(MapStrings));
end;

procedure TXsltOutputProperties.AddMapping(Code: Cardinal; const S: TLandrixXmlUtf8);
var
  I: Integer;
begin
  for I := 0 to Integer(Length(MapChars)) - 1 do
    if MapChars[I] = Code then
    begin
      MapStrings[I] := S;
      Exit;
    end;
  I := Integer(Length(MapChars));
  SetLength(MapChars, I + 1);
  SetLength(MapStrings, I + 1);
  MapChars[I] := Code;
  MapStrings[I] := S;
end;

procedure TXsltOutputProperties.AddMappings(Source: TXsltOutputProperties);
var
  I: Integer;
begin
  for I := 0 to Integer(Length(Source.MapChars)) - 1 do
    AddMapping(Source.MapChars[I], Source.MapStrings[I]);
end;

procedure TXsltOutputProperties.AddCDataElements(const Names: TLandrixXmlUtf8);
var
  Old: TLandrixXmlUtf8;
begin
  if Names = '' then
    Exit;
  Old := Value('cdata-section-elements', '');
  if Old = '' then
    SetValue('cdata-section-elements', Names)
  else
    SetValue('cdata-section-elements', Old + ' ' + Names);
end;

{ --- serializer ------------------------------------------------------------ }

{ S without leading and trailing XML white space }
function Trim8Ws(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  A, B: Integer;
begin
  A := 1;
  B := Length(S);
  while (A <= B) and (S[A] in [#9, #10, #13, ' ']) do
    Inc(A);
  while (B >= A) and (S[B] in [#9, #10, #13, ' ']) do
    Dec(B);
  Result := Copy(S, A, B - A + 1);
end;

{ whether S contains the byte C }
function Pos8Byte(C: AnsiChar; const S: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 1 to Length(S) do
    if S[I] = C then
      Exit;
  Result := False;
end;

type
  TSerializer = class
  private
    FTree: TLandrixXmlXPathTree;
    FStream: TStream;
    FBuffer: TLandrixXmlUtf8;
    FLength: Integer;
    FIndent: Boolean;
    { the state of the indentation, as Saxon keeps it: the last thing
      written was a start tag, an end tag (or the XML declaration); no
      line break since the last start tag }
    FAfterStart: Boolean;
    FAfterEnd: Boolean;
    FSameLine: Boolean;
    FLevel: Integer;
    { the level of the element with xml:space="preserve" that stops the
      indentation, -1 for none }
    FSuppressedAt: Integer;
    { white space text held back: dropped where a line break is written }
    FPending: TLandrixXmlUtf8;
    FHasPending: Boolean;
    { the highest code point of the encoding, and whether a character above
      it is written as a character reference (text and attribute values)
      or an error }
    FMaxChar: Cardinal;
    FEscape: Boolean;
    { the character map: the characters (those below 80 also in
      FAsciiMap, -1 for none), their strings; FInMap while a text is
      mapped; FPlain: the text method (nothing escaped) }
    FMapChars: TXsltCardinalArray;
    FMapStrings: TLandrixXmlUtf8Array;
    FAsciiMap: array[0..127] of Integer;
    FHasMap: Boolean;
    FInMap: Boolean;
    FPlain: Boolean;
    { cdata-section-elements: the Clark names of the elements whose text
      is written as CDATA sections }
    FCData: TLandrixXmlUtf8Array;
    procedure SetMap(Props: TXsltOutputProperties);
    procedure SetCData(Props: TXsltOutputProperties);
    function InCData(I: Integer): Boolean;
    procedure PutCData(const S: TLandrixXmlUtf8);
    function MappedAt(const S: TLandrixXmlUtf8; I: Integer; out N: Integer): Integer;
    procedure PutMapped(const S: TLandrixXmlUtf8; Attribute: Boolean);
    procedure PutUnmapped(const S: TLandrixXmlUtf8);
    procedure PutAttr(const Name, Value: TLandrixXmlUtf8);
    function MappedValue(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
    function MappedCount(const S: TLandrixXmlUtf8): Integer;
    function HasMapped(const S: TLandrixXmlUtf8): Boolean;
    procedure Escape(const S: TLandrixXmlUtf8; Attribute: Boolean); virtual;
    procedure PutBytes(const S: TLandrixXmlUtf8);
    procedure PutEncoded(const S: TLandrixXmlUtf8);
    procedure Put(const S: TLandrixXmlUtf8);
    procedure Flush;
    procedure Spaces(N: Integer);
    procedure Indent;
    procedure FlushPending;
    procedure PutEscaped(const S: TLandrixXmlUtf8; Attribute: Boolean);
    procedure PutText(const S: TLandrixXmlUtf8);
    procedure Node(I: Integer);
    procedure Element(I: Integer);
  public
    constructor Create(Tree: TLandrixXmlXPathTree; Stream: TStream; Indent: Boolean);
  end;

constructor TSerializer.Create(Tree: TLandrixXmlXPathTree; Stream: TStream; Indent: Boolean);
begin
  inherited Create;
  FTree := Tree;
  FStream := Stream;
  FIndent := Indent;
  FSuppressedAt := -1;
  FMaxChar := $10FFFF;
  SetLength(FBuffer, 65536);
end;

procedure TSerializer.SetMap(Props: TXsltOutputProperties);
var
  I: Integer;
begin
  for I := 0 to 127 do
    FAsciiMap[I] := -1;
  FMapChars := Copy(Props.MapChars, 0, Length(Props.MapChars));
  FMapStrings := Copy(Props.MapStrings, 0, Length(Props.MapStrings));
  for I := 0 to Integer(Length(FMapChars)) - 1 do
    if FMapChars[I] < 128 then
      FAsciiMap[FMapChars[I]] := I;
  FHasMap := Length(FMapChars) > 0;
end;

procedure TSerializer.SetCData(Props: TXsltOutputProperties);
var
  V: TLandrixXmlUtf8;
  I, Start, N: Integer;
begin
  V := Props.Value('cdata-section-elements', '');
  N := 0;
  I := 1;
  while I <= Length(V) do
  begin
    while (I <= Length(V)) and (V[I] = ' ') do
      Inc(I);
    Start := I;
    while (I <= Length(V)) and (V[I] <> ' ') do
      Inc(I);
    if I > Start then
    begin
      SetLength(FCData, N + 1);
      FCData[N] := Copy(V, Start, I - Start);
      Inc(N);
    end;
  end;
end;

{ whether the text node I is a child of a cdata-section-elements element }
function TSerializer.InCData(I: Integer): Boolean;
var
  P, K: Integer;
  Name: TLandrixXmlUtf8;
begin
  Result := False;
  if Length(FCData) = 0 then
    Exit;
  P := FTree.Parent[I];
  if (P < 0) or (FTree.Kind[P] <> xnkElement) then
    Exit;
  if FTree.NamespaceUriUtf8(P) = '' then
    Name := FTree.LocalNameUtf8(P)
  else
    Name := '{' + FTree.NamespaceUriUtf8(P) + '}' + FTree.LocalNameUtf8(P);
  for K := 0 to Integer(Length(FCData)) - 1 do
    if FCData[K] = Name then
    begin
      Result := True;
      Exit;
    end;
end;

{ a text in CDATA sections, as Saxon writes it: nothing escaped or mapped;
  "]]>" split between two sections; a character the encoding lacks as a
  character reference between sections (no empty section) }
procedure TSerializer.PutCData(const S: TLandrixXmlUtf8);
var
  I, N, Start: Integer;
  Code: Cardinal;
  Open: Boolean;
begin
  Open := False;
  Start := 1;
  I := 1;
  while I <= Length(S) do
  begin
    N := 1;
    Code := Ord(S[I]);
    if Code >= $80 then
    begin
      N := LandrixXmlDecodeUtf8(PAnsiChar(S) + I - 1, Length(S) - I + 1, Code);
      if N = 0 then
      begin
        N := 1;
        Code := $FFFD;
      end;
    end;
    if Code > FMaxChar then
    begin
      if Open then
      begin
        Put(Copy(S, Start, I - Start));
        Put(']]>');
        Open := False;
      end;
      Put('&#x' + LandrixXmlStringToUtf8(LowerCase(IntToHex(Code, 1))) + ';');
      Inc(I, N);
      Continue;
    end;
    if not Open then
    begin
      Put('<![CDATA[');
      Open := True;
      Start := I;
    end;
    if (S[I] = ']') and (I + 2 <= Length(S)) and (S[I + 1] = ']') and (S[I + 2] = '>') then
    begin
      Put(Copy(S, Start, I + 2 - Start));
      Put(']]><![CDATA[');
      Start := I + 2;
      Inc(I, 2);
    end
    else
      Inc(I, N);
  end;
  if Open then
  begin
    Put(Copy(S, Start, Length(S) - Start + 1));
    Put(']]>');
  end;
end;

{ the index of the mapped character at S[I] (-1: none); N its length in
  bytes }
function TSerializer.MappedAt(const S: TLandrixXmlUtf8; I: Integer; out N: Integer): Integer;
var
  Code: Cardinal;
  K: Integer;
begin
  Result := -1;
  N := 1;
  if Ord(S[I]) < $80 then
  begin
    Result := FAsciiMap[Ord(S[I])];
    Exit;
  end;
  N := LandrixXmlDecodeUtf8(PAnsiChar(S) + I - 1, Length(S) - I + 1, Code);
  if N = 0 then
  begin
    N := 1;
    Exit;
  end;
  for K := 0 to Integer(Length(FMapChars)) - 1 do
    if FMapChars[K] = Code then
    begin
      Result := K;
      Exit;
    end;
end;

{ text or an attribute value with the character map: the parts between
  mapped characters escaped, the strings of the mapped characters as they
  are (SERE0008 for a character of them the encoding does not have) }
procedure TSerializer.PutMapped(const S: TLandrixXmlUtf8; Attribute: Boolean);
var
  I, N, K, Start: Integer;
  Saved: Boolean;
begin
  FInMap := True;
  try
    Start := 1;
    I := 1;
    while I <= Length(S) do
    begin
      K := MappedAt(S, I, N);
      if K >= 0 then
      begin
        Escape(Copy(S, Start, I - Start), Attribute);
        Saved := FEscape;
        FEscape := False;
        try
          Put(FMapStrings[K]);
        finally
          FEscape := Saved;
        end;
        Start := I + N;
      end;
      Inc(I, N);
    end;
    Escape(Copy(S, Start, Length(S) - Start + 1), Attribute);
  finally
    FInMap := False;
  end;
end;

{ whether S has a character of the character map }
function TSerializer.HasMapped(const S: TLandrixXmlUtf8): Boolean;
var
  I, N: Integer;
begin
  Result := True;
  I := 1;
  while I <= Length(S) do
  begin
    if MappedAt(S, I, N) >= 0 then
      Exit;
    Inc(I, N);
  end;
  Result := False;
end;

{ Name="Value", the value escaped and mapped; in apostrophes for a value
  with a mapped character that has a quotation mark and no apostrophe once
  mapped (Saxon) }
procedure TSerializer.PutAttr(const Name, Value: TLandrixXmlUtf8);
var
  Mapped, Delimiter: TLandrixXmlUtf8;
begin
  Delimiter := '"';
  if FHasMap and HasMapped(Value) then
  begin
    Mapped := MappedValue(Value);
    if Pos8Byte('"', Mapped) and not Pos8Byte(#39, Mapped) then
      Delimiter := #39;
  end;
  Put(Name + '=' + Delimiter);
  Escape(Value, True);
  Put(Delimiter);
end;

{ S with the strings of its mapped characters (S without a map) }
function TSerializer.MappedValue(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I, N, K: Integer;
begin
  Result := S;
  if not FHasMap or not HasMapped(S) then
    Exit;
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    K := MappedAt(S, I, N);
    if K >= 0 then
      Result := Result + FMapStrings[K]
    else
      Result := Result + Copy(S, I, N);
    Inc(I, N);
  end;
end;

{ the number of mapped characters in S }
function TSerializer.MappedCount(const S: TLandrixXmlUtf8): Integer;
var
  I, N: Integer;
begin
  Result := 0;
  if not FHasMap then
    Exit;
  I := 1;
  while I <= Length(S) do
  begin
    if MappedAt(S, I, N) >= 0 then
      Inc(Result);
    Inc(I, N);
  end;
end;

{ an attribute value without the character map (a namespace URI, an
  escaped URI) }
procedure TSerializer.PutUnmapped(const S: TLandrixXmlUtf8);
var
  Saved: Boolean;
begin
  Saved := FInMap;
  FInMap := True;
  try
    Escape(S, True);
  finally
    FInMap := Saved;
  end;
end;

procedure TSerializer.Escape(const S: TLandrixXmlUtf8; Attribute: Boolean);
begin
  if FPlain then
    Put(S)
  else
    PutEscaped(S, Attribute);
end;

procedure TSerializer.Flush;
begin
  if FLength > 0 then
    FStream.WriteBuffer(PAnsiChar(FBuffer)^, FLength);
  FLength := 0;
end;

procedure TSerializer.Put(const S: TLandrixXmlUtf8);
var
  I: Integer;
begin
  if FMaxChar < $10FFFF then
    for I := 1 to Length(S) do
      if Ord(S[I]) >= $80 then
      begin
        PutEncoded(S);
        Exit;
      end;
  PutBytes(S);
end;

{ S (UTF-8, with a byte above 7F) in an encoding other than UTF-8 }
procedure TSerializer.PutEncoded(const S: TLandrixXmlUtf8);
var
  I, N, Count: Integer;
  Code: Cardinal;
  R: TLandrixXmlUtf8;
begin
  R := '';
  SetLength(R, Length(S));
  Count := 0;
  I := 1;
  while I <= Length(S) do
  begin
    if Ord(S[I]) < $80 then
    begin
      Inc(Count);
      R[Count] := S[I];
      Inc(I);
      Continue;
    end;
    N := LandrixXmlDecodeUtf8(PAnsiChar(S) + I - 1, Length(S) - I + 1, Code);
    if N = 0 then
    begin
      N := 1;
      Code := $FFFD;
    end;
    if Code <= FMaxChar then
    begin
      Inc(Count);
      R[Count] := AnsiChar(Code);
    end
    else if FEscape then
    begin
      SetLength(R, Count);
      R := R + '&#x' + LandrixXmlStringToUtf8(LowerCase(IntToHex(Code, 1))) + ';';
      Count := Length(R);
      SetLength(R, Count + Length(S) - I + 1);
    end
    else
      raise ELandrixXmlXPathError.CreateXPath('SERE0008', 'output character not available in this encoding (x' +
        LowerCase(IntToHex(Code, 1)) + ')');
    Inc(I, N);
  end;
  SetLength(R, Count);
  PutBytes(R);
end;

procedure TSerializer.PutBytes(const S: TLandrixXmlUtf8);
var
  N: Integer;
begin
  N := Length(S);
  if N = 0 then
    Exit;
  if FLength + N > Length(FBuffer) then
  begin
    Flush;
    if N > Length(FBuffer) then
    begin
      FStream.WriteBuffer(PAnsiChar(S)^, N);
      Exit;
    end;
  end;
  Move(PAnsiChar(S)^, FBuffer[FLength + 1], N);
  Inc(FLength, N);
end;

{ a line break and N spaces }
procedure TSerializer.Spaces(N: Integer);
var
  S: TLandrixXmlUtf8;
  I: Integer;
begin
  S := '';
  SetLength(S, 1 + N);
  S[1] := #10;
  for I := 2 to Length(S) do
    S[I] := ' ';
  Put(S);
end;

{ a line break and the indentation of the level (instead of the white
  space held back), none where xml:space keeps the white space }
procedure TSerializer.Indent;
begin
  if FSuppressedAt >= 0 then
  begin
    FlushPending;
    Exit;
  end;
  FHasPending := False;
  FPending := '';
  Spaces(3 * FLevel);
  FSameLine := False;
end;

procedure TSerializer.FlushPending;
begin
  if not FHasPending then
    Exit;
  FHasPending := False;
  PutText(FPending);
  FPending := '';
end;

{ text (Attribute False) or an attribute value escaped as Saxon's XML
  emitter does: < > & and carriage returns (in attributes also " and the
  other white space), U+007F to U+009F and U+2028 as character references
  in every encoding }
procedure TSerializer.PutEscaped(const S: TLandrixXmlUtf8; Attribute: Boolean);
var
  I, Start, N: Integer;
  R: TLandrixXmlUtf8;
  Saved: Boolean;
begin
  if FHasMap and not FInMap then
  begin
    PutMapped(S, Attribute);
    Exit;
  end;
  Saved := FEscape;
  FEscape := True;
  Start := 1;
  I := 1;
  while I <= Length(S) do
  begin
    R := '';
    N := 1;
    case S[I] of
      '<': R := '&lt;';
      '>': R := '&gt;';
      '&': R := '&amp;';
      #13: R := '&#xD;';
      #127: R := '&#x7f;';
      '"':
        if Attribute then
          R := '&#34;';
      #9:
        if Attribute then
          R := '&#x9;';
      #10:
        if Attribute then
          R := '&#xA;';
      #$C2:
        if (I < Length(S)) and (Ord(S[I + 1]) >= $80) and (Ord(S[I + 1]) <= $9F) then
        begin
          R := '&#x' + LandrixXmlStringToUtf8(LowerCase(IntToHex(Ord(S[I + 1]), 2))) + ';';
          N := 2;
        end;
      #$E2:
        if (I + 2 <= Length(S)) and (S[I + 1] = #$80) and (S[I + 2] = #$A8) then
        begin
          R := '&#x2028;';
          N := 3;
        end;
    end;
    if R <> '' then
    begin
      Put(Copy(S, Start, I - Start));
      Put(R);
      Start := I + N;
    end;
    Inc(I, N);
  end;
  Put(Copy(S, Start, Length(S) - Start + 1));
  FEscape := Saved;
end;

procedure TSerializer.PutText(const S: TLandrixXmlUtf8);
begin
  PutEscaped(S, False);
end;

function IsWhiteSpace(const S: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to Length(S) do
    if not (S[I] in [#9, #10, #13, ' ']) then
      Exit;
  Result := True;
end;

{ the declarations in the order of their prefixes (as Saxon writes them;
  the default namespace first) }
procedure SortDeclarations(var Prefixes, Uris: TLandrixXmlUtf8Array);
var
  I, J: Integer;
  P, U: TLandrixXmlUtf8;
begin
  for I := 1 to Integer(Length(Prefixes)) - 1 do
  begin
    P := Prefixes[I];
    U := Uris[I];
    J := I - 1;
    while (J >= 0) and (CompareStr(LandrixXmlUtf8ToString(Prefixes[J]), LandrixXmlUtf8ToString(P)) > 0) do
    begin
      Prefixes[J + 1] := Prefixes[J];
      Uris[J + 1] := Uris[J];
      Dec(J);
    end;
    Prefixes[J + 1] := P;
    Uris[J + 1] := U;
  end;
end;

{ the length of S as Java counts it (UTF-16 code units) }
function JavaLength(const S: TLandrixXmlUtf8): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) do
    if Ord(S[I]) and $C0 <> $80 then
    begin
      Inc(Result);
      if Ord(S[I]) >= $F0 then
        Inc(Result);
    end;
end;

{ An element, indented as Saxon does: a line break before a start tag
  that follows a start or end tag, before an end tag, a comment or a
  processing instruction that follows an end tag; white space text where
  a line break goes is dropped; nothing of it inside an element with
  xml:space="preserve". The declarations and attributes of a start tag
  whose names and values are longer than 80 characters (counted as Saxon
  does) go on lines of their own, under the first one. }
procedure TSerializer.Element(I: Integer);
var
  Prefixes, Uris: TLandrixXmlUtf8Array;
  K, C, Len, AttrIndent: Integer;
  Wrap, First: Boolean;
  Name: TLandrixXmlUtf8;

  procedure Separator;
  begin
    if First or not Wrap then
      Put(' ')
    else
      Spaces(AttrIndent);
    First := False;
  end;

begin
  if FIndent then
  begin
    if FAfterStart or FAfterEnd then
      Indent
    else
      FlushPending;
  end;
  Inc(FLevel);
  Name := FTree.NameUtf8(I);
  FTree.GetDeclarations(I, Prefixes, Uris);
  Wrap := False;
  AttrIndent := 0;
  if FIndent then
  begin
    if FSuppressedAt < 0 then
      for K := I + 1 to I + FTree.AttributeCount[I] do
        if (FTree.NamespaceUriUtf8(K) = LandrixXmlNamespaceXml) and (FTree.LocalNameUtf8(K) = 'space') and
          (Trim8Ws(FTree.ValueUtf8(K)) = 'preserve') then
          FSuppressedAt := FLevel;
    FSameLine := True;
    FAfterStart := True;
    FAfterEnd := False;
    if FSuppressedAt < 0 then
    begin
      Len := 0;
      for K := 0 to Integer(Length(Prefixes)) - 1 do
        if Prefixes[K] = '' then
          Inc(Len, 9 + JavaLength(Uris[K]))
        else
          Inc(Len, JavaLength(Prefixes[K]) + 10 + JavaLength(Uris[K]));
      for K := I + 1 to I + FTree.AttributeCount[I] do
      begin
        { the mapped value, and two for each mapped character (Saxon counts
          the markers around its strings) }
        Inc(Len, JavaLength(FTree.LocalNameUtf8(K)) + JavaLength(MappedValue(FTree.ValueUtf8(K))) +
          2 * MappedCount(FTree.ValueUtf8(K)) + 4);
        if FTree.PrefixUtf8(K) = '' then
          Inc(Len, 4)
        else
          Inc(Len, JavaLength(FTree.PrefixUtf8(K)) + 5);
      end;
      Wrap := Len > 80;
      AttrIndent := 3 * (FLevel - 1) + 2 + JavaLength(Name);
    end;
  end;
  Put('<' + Name);
  SortDeclarations(Prefixes, Uris);
  First := True;
  for K := 0 to Integer(Length(Prefixes)) - 1 do
  begin
    Separator;
    if Prefixes[K] = '' then
      Put('xmlns="')
    else
      Put('xmlns:' + Prefixes[K] + '="');
    PutUnmapped(Uris[K]);
    Put('"');
  end;
  for K := I + 1 to I + FTree.AttributeCount[I] do
  begin
    Separator;
    PutAttr(FTree.NameUtf8(K), FTree.ValueUtf8(K));
  end;
  C := FTree.FirstChild(I);
  if C >= 0 then
  begin
    Put('>');
    while C >= 0 do
    begin
      Node(C);
      C := FTree.NextSibling[C];
    end;
  end;
  Dec(FLevel);
  if FIndent then
  begin
    if FAfterEnd and not FSameLine then
      Indent
    else
      FlushPending;
  end;
  if FTree.FirstChild(I) < 0 then
    Put('/>')
  else
    Put('</' + Name + '>');
  if FIndent then
  begin
    FSameLine := False;
    FAfterEnd := True;
    FAfterStart := False;
    if FLevel = FSuppressedAt - 1 then
      FSuppressedAt := -1;
  end;
end;

procedure TSerializer.Node(I: Integer);
var
  C: Integer;
  V: TLandrixXmlUtf8;
  Cdata: Boolean;
begin
  case FTree.Kind[I] of
    xnkDocument:
      begin
        C := FTree.FirstChild(I);
        while C >= 0 do
        begin
          Node(C);
          C := FTree.NextSibling[C];
        end;
      end;
    xnkElement:
      Element(I);
    xnkText:
      begin
        V := FTree.ValueUtf8(I);
        Cdata := InCData(I);
        if FIndent then
        begin
          { white space with a mapped character, or in a CDATA section, is
            text (Saxon) }
          if (FSuppressedAt < 0) and IsWhiteSpace(V) and not (FHasMap and HasMapped(V)) and not Cdata then
          begin
            FlushPending;
            FPending := V;
            FHasPending := True;
            Exit;
          end;
          FlushPending;
          if Pos8Byte(#10, V) then
            FSameLine := False;
          FAfterStart := False;
          FAfterEnd := False;
        end;
        if Cdata then
          PutCData(V)
        else
          PutText(V);
      end;
    xnkComment, xnkProcessingInstruction:
      begin
        if FIndent then
        begin
          if FAfterEnd then
            Indent
          else
            FlushPending;
        end;
        if FTree.Kind[I] = xnkComment then
          Put('<!--' + FTree.ValueUtf8(I) + '-->')
        else if FTree.ValueUtf8(I) = '' then
          Put('<?' + FTree.LocalNameUtf8(I) + '?>')
        else
          Put('<?' + FTree.LocalNameUtf8(I) + ' ' + FTree.ValueUtf8(I) + '?>');
      end;
  else
    { attributes belong to their element }
  end;
end;

{ --- method html ------------------------------------------------------------ }

const
  { the element classes of Saxon's HTML indenter: inline elements (no line
    break around them) and formatted ones (nothing changed inside) }
  HtmlInline = ' a abbr acronym applet area audio b basefont bdi bdo big br button canvas cite code data ' +
    'datalist del dfn em embed font i iframe img input ins kbd label map mark math meter noscript object ' +
    'output picture progress q ruby s samp script select small span strike strong sub sup svg template ' +
    'textarea time tt u var video wbr ';
  HtmlFormatted = ' pre script style textarea title xmp ';
  { the void elements of HTML5: no end tag }
  HtmlEmpty = ' area base basefont br col embed frame hr img input isindex keygen link meta param source ' +
    'track wbr ';
  { element+attribute written as the name alone when its value is the name
    (* any element) }
  HtmlBoolean = ' *+hidden area+nohref audio+autoplay audio+controls audio+loop audio+muted button+disabled ' +
    'button+autofocus button+formnovalidate details+open dialog+open dir+compact dl+compact ' +
    'fieldset+disabled form+novalidate frame+noresize hr+noshade img+ismap input+checked input+disabled ' +
    'input+multiple input+readonly input+required input+autofocus input+formnovalidate iframe+seamless ' +
    'keygen+autofocus keygen+disabled menu+compact object+declare object+typemustmatch ol+compact ' +
    'ol+reversed optgroup+disabled option+selected option+disabled script+defer script+async ' +
    'select+multiple select+disabled select+autofocus select+required style+scoped td+nowrap ' +
    'textarea+disabled textarea+readonly textarea+autofocus textarea+required th+nowrap track+default ' +
    'ul+compact video+autoplay video+controls video+loop video+muted ';
  { element+attribute holding a URI (escape-uri-attributes) }
  HtmlUri = ' form+action object+archive body+background q+cite blockquote+cite del+cite ins+cite ' +
    'object+classid object+codebase applet+codebase object+data button+datasrc div+datasrc input+datasrc ' +
    'object+datasrc select+datasrc span+datasrc table+datasrc textarea+datasrc script+for a+href a+name ' +
    'area+href link+href base+href img+longdesc frame+longdesc iframe+longdesc head+profile script+src ' +
    'input+src frame+src iframe+src img+src img+usemap input+usemap object+usemap ';
  XhtmlNamespace = 'http://www.w3.org/1999/xhtml';
  { the elements of XHTML 1.0 with empty content: <br /> (method xhtml) }
  XhtmlEmpty = ' area base basefont br col frame hr img input isindex link meta param ';

type
  { Writes a tree as Saxon HE's HTML5 serializer and HTML indenter do;
    with FXhtml as its XHTML serializer (XML names, namespaces and
    escaping, <br /> for the empty XHTML elements, the HTML indentation) }
  THtmlSerializer = class(TSerializer)
  private
    FXhtml: Boolean;
    FHtmlLevel: Integer;
    FSameLine: Boolean;
    FAfterInline: Boolean;
    FAfterEndElement: Boolean;
    FInFormatted: Boolean;
    { per open element: 1 inline, 2 formatted }
    FFlags: array of Integer;
    { inside script or style (Saxon: greater than zero) }
    FInScript: Integer;
    FStarted: Boolean;
    { a start tag not yet closed with ">" }
    FOpenTag: Boolean;
    FEscapeUris: Boolean;
    FContentType: Boolean;
    FMediaType: TLandrixXmlUtf8;
    FEncoding: TLandrixXmlUtf8;
    { the default namespace of the output per open element }
    FDefaults: TLandrixXmlUtf8Array;
    { per output element: the prefixes of its XHTML attributes }
    FXhtmlPrefixes: TLandrixXmlUtf8Array;
    FNsDepth: Integer;
    procedure CloseTag;
    procedure HtmlIndent;
    procedure HtmlText(const S: TLandrixXmlUtf8; Attribute: Boolean);
    procedure Escape(const S: TLandrixXmlUtf8; Attribute: Boolean); override;
    procedure IndentedText(const S: TLandrixXmlUtf8);
    procedure StartTag(const Name, Local: TLandrixXmlUtf8; IsHtml: Boolean; I: Integer);
    procedure EndTag(const Name, Local: TLandrixXmlUtf8; IsHtml: Boolean);
    procedure ContentTypeMeta(const Prefix: TLandrixXmlUtf8; IsHtml: Boolean);
    procedure XhtmlStartTag(const Name, Local: TLandrixXmlUtf8; I: Integer);
    procedure XhtmlEndTag(const Name, Local: TLandrixXmlUtf8; XhtmlElement: Boolean);
    procedure HtmlNode(I: Integer);
  end;

{ the lower case of the ASCII letters of S }
function Lower8(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if Result[I] in ['A'..'Z'] then
      Result[I] := AnsiChar(Ord(Result[I]) + 32);
end;

function InList(const List: string; const Name: TLandrixXmlUtf8): Boolean;
begin
  Result := Pos(' ' + LandrixXmlUtf8ToString(Name) + ' ', List) > 0;
end;

{ escape-html-uri: the characters outside 32..126 as %HH of their UTF-8 bytes }
function EscapeHtmlUri(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
const
  Hex: string = '0123456789ABCDEF';
var
  I: Integer;
  V: TLandrixXmlUtf8;
begin
  Result := '';
  { in NFC first (Saxon) }
  V := LandrixXmlNormalizeUtf8(S, xnfNfc);
  for I := 1 to Length(V) do
    if (Ord(V[I]) < 32) or (Ord(V[I]) > 126) then
      Result := Result + '%' + LandrixXmlStringToUtf8(Hex[Ord(V[I]) div 16 + 1] + Hex[Ord(V[I]) mod 16 + 1])
    else
      Result := Result + Copy(V, I, 1);
end;

procedure THtmlSerializer.CloseTag;
begin
  if FOpenTag then
  begin
    Put('>');
    FOpenTag := False;
  end;
end;

procedure THtmlSerializer.HtmlIndent;
begin
  CloseTag;
  Spaces(3 * FHtmlLevel);
  FSameLine := False;
end;

{ Text as Saxon's HTML emitter escapes it: in text < > &, in attributes
  > & (not before "{") " and line breaks; U+00A0 as &nbsp;, the C1
  controls as character references; nothing inside script and style }
procedure THtmlSerializer.HtmlText(const S: TLandrixXmlUtf8; Attribute: Boolean);
var
  I, Start, N: Integer;
  Code: Cardinal;
  R: TLandrixXmlUtf8;
  Drop, Saved: Boolean;
begin
  if FHasMap and not FInMap then
  begin
    PutMapped(S, Attribute);
    Exit;
  end;
  if FXhtml then
  begin
    PutEscaped(S, Attribute);
    Exit;
  end;
  if FInScript > 0 then
  begin
    Put(S);
    Exit;
  end;
  Saved := FEscape;
  FEscape := True;
  Start := 1;
  I := 1;
  while I <= Length(S) do
  begin
    R := '';
    Drop := False;
    N := 1;
    case S[I] of
      '<':
        if not Attribute then
          R := '&lt;';
      '>':
        R := '&gt;';
      '&':
        if not Attribute or (I = Length(S)) or (S[I + 1] <> '{') then
          R := '&amp;';
      '"':
        if Attribute then
          R := '&#34;';
      #10:
        if Attribute then
          R := '&#xA;';
      #9:
        if Attribute then
          R := '&#x9;';
      #13:
        R := '&#xD;';
      #$C2:
        begin
          N := LandrixXmlDecodeUtf8(PAnsiChar(S) + I - 1, Length(S) - I + 1, Code);
          if N = 0 then
            N := 1
          else if Code = 160 then
            R := '&nbsp;'
          else if (Code >= 127) and (Code < 160) then
            R := '&#x' + Lower8(LandrixXmlStringToUtf8(IntToHex(Code, 1))) + ';';
        end;
      #127:
        { Saxon writes nothing for DEL }
        Drop := True;
    end;
    if (R <> '') or Drop then
    begin
      Put(Copy(S, Start, I - Start));
      Put(R);
      Start := I + N;
    end;
    Inc(I, N);
  end;
  Put(Copy(S, Start, Length(S) - Start + 1));
  FEscape := Saved;
end;

procedure THtmlSerializer.Escape(const S: TLandrixXmlUtf8; Attribute: Boolean);
begin
  HtmlText(S, Attribute);
end;

{ text outside formatted elements: a line break, or a space after more than
  80 characters of the text, becomes a line break with the indentation of
  the level (the spaces after it dropped), as Saxon's HTML indenter does }
procedure THtmlSerializer.IndentedText(const S: TLandrixXmlUtf8);
var
  I, Start, Count, StartCount: Integer;
begin
  Start := 1;
  Count := 0;
  StartCount := 0;
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = #10) or (S[I] = ' ') and (Count - StartCount > 80) then
    begin
      FSameLine := False;
      CloseTag;
      HtmlText(Copy(S, Start, I - Start), False);
      HtmlIndent;
      Inc(I);
      Inc(Count);
      while (I <= Length(S)) and (S[I] = ' ') do
      begin
        Inc(I);
        Inc(Count);
      end;
      Start := I;
      StartCount := Count;
      Continue;
    end;
    { characters, not bytes }
    if Ord(S[I]) and $C0 <> $80 then
      Inc(Count);
    Inc(I);
  end;
  if Start <= Length(S) then
  begin
    CloseTag;
    HtmlText(Copy(S, Start, Length(S) - Start + 1), False);
  end;
end;

{ whether List (words between spaces, a space first and last) holds W }
function HasWord(const List, W: TLandrixXmlUtf8): Boolean;
var
  I, J: Integer;
begin
  Result := True;
  for I := 1 to Length(List) - Length(W) - 1 do
    if List[I] = ' ' then
    begin
      J := 1;
      while (J <= Length(W)) and (List[I + J] = W[J]) do
        Inc(J);
      if (J > Length(W)) and (List[I + J] = ' ') then
        Exit;
    end;
  Result := False;
end;

procedure THtmlSerializer.StartTag(const Name, Local: TLandrixXmlUtf8; IsHtml: Boolean; I: Integer);
var
  Prefixes, Uris: TLandrixXmlUtf8Array;
  K, J: Integer;
  AName, ALocal, V, Default, Target, Parent, Mine: TLandrixXmlUtf8;
begin
  Mine := '';
  CloseTag;
  Put('<' + Name);
  if FNsDepth > 0 then
    Default := FDefaults[FNsDepth - 1]
  else
    Default := '';
  if I >= 0 then
  begin
    { the declarations without the prefixes of the XHTML namespace; the
      default namespace of the element's name declared where it differs
      (an XHTML element loses its prefix) }
    FTree.GetDeclarations(I, Prefixes, Uris);
    K := 0;
    for J := 0 to Integer(Length(Prefixes)) - 1 do
      if (Prefixes[J] <> '') and (Uris[J] <> XhtmlNamespace) then
      begin
        Prefixes[K] := Prefixes[J];
        Uris[K] := Uris[J];
        Inc(K);
      end;
    SetLength(Prefixes, K);
    SetLength(Uris, K);
    { an attribute in the XHTML namespace keeps its prefix: declared
      unless the parent has an attribute with that prefix too (Saxon keeps
      an XHTML prefix in scope only on the elements that use it) }
    if FNsDepth > 0 then
      Parent := FXhtmlPrefixes[FNsDepth - 1]
    else
      Parent := '';
    Mine := ' ';
    for J := I + 1 to I + FTree.AttributeCount[I] do
      if FTree.NamespaceUriUtf8(J) = XhtmlNamespace then
      begin
        AName := FTree.NameUtf8(J);
        K := 1;
        while (K <= Length(AName)) and (AName[K] <> ':') do
          Inc(K);
        if K > Length(AName) then
          K := 1;
        AName := Copy(AName, 1, K - 1);
        V := '';
        for K := 0 to Integer(Length(Prefixes)) - 1 do
          if Prefixes[K] = AName then
            V := AName;
        if (AName <> '') and not HasWord(Mine, AName) then
          Mine := Mine + AName + ' ';
        if (AName <> '') and (V = '') and not HasWord(Parent, AName) then
        begin
          K := Integer(Length(Prefixes));
          SetLength(Prefixes, K + 1);
          SetLength(Uris, K + 1);
          Prefixes[K] := AName;
          Uris[K] := XhtmlNamespace;
        end;
      end;
    K := Integer(Length(Prefixes));
    { the default namespace: XHTML for an XHTML element, else the
      element's own unless that is XHTML; declared where the output's
      differs }
    if FTree.NamespaceUriUtf8(I) = XhtmlNamespace then
      Target := XhtmlNamespace
    else if not FTree.LookupNamespace(I, '', Target) or (Target = XhtmlNamespace) then
      Target := '';
    if Target <> Default then
    begin
      SetLength(Prefixes, K + 1);
      SetLength(Uris, K + 1);
      Prefixes[K] := '';
      Uris[K] := Target;
    end;
    SortDeclarations(Prefixes, Uris);
    for K := 0 to Integer(Length(Prefixes)) - 1 do
    begin
      if Prefixes[K] = '' then
      begin
        Put(' xmlns="');
        Default := Uris[K];
      end
      else
        Put(' xmlns:' + Prefixes[K] + '="');
      PutUnmapped(Uris[K]);
      Put('"');
    end;
    for K := I + 1 to I + FTree.AttributeCount[I] do
    begin
      AName := FTree.NameUtf8(K);
      ALocal := Lower8(FTree.LocalNameUtf8(K));
      V := FTree.ValueUtf8(K);
      { minimized unless a character of it is mapped (Saxon) }
      if IsHtml and (FTree.NamespaceUriUtf8(K) = '') and (Lower8(V) = ALocal) and
        (InList(HtmlBoolean, Local + '+' + ALocal) or InList(HtmlBoolean, '*+' + ALocal)) and
        not (FHasMap and HasMapped(V)) then
      begin
        Put(' ' + AName);
        Continue;
      end;
      { by the names of an element without a prefix, in any namespace
        (Saxon) }
      if FEscapeUris and (FTree.NamespaceUriUtf8(K) = '') and InList(HtmlUri, Local + '+' + ALocal) and
        not Pos8Byte(':', FTree.NameUtf8(I)) then
      begin
        { an escaped URI gets no character map (Saxon) }
        V := EscapeHtmlUri(V);
        Put(' ' + AName + '="');
        PutUnmapped(V);
        Put('"');
        Continue;
      end;
      Put(' ');
      PutAttr(AName, V);
    end;
  end;
  if FNsDepth >= Length(FDefaults) then
  begin
    SetLength(FDefaults, 2 * FNsDepth + 8);
    SetLength(FXhtmlPrefixes, 2 * FNsDepth + 8);
  end;
  FDefaults[FNsDepth] := Default;
  FXhtmlPrefixes[FNsDepth] := Mine;
  Inc(FNsDepth);
  FOpenTag := True;
  if IsHtml and ((Local = 'script') or (Local = 'style')) then
    FInScript := 0;
  Inc(FInScript);
end;

procedure THtmlSerializer.EndTag(const Name, Local: TLandrixXmlUtf8; IsHtml: Boolean);
begin
  Dec(FNsDepth);
  Dec(FInScript);
  if FInScript = 0 then
    FInScript := -1000000;
  if IsHtml and InList(HtmlEmpty, Local) then
  begin
    CloseTag;
    Exit;
  end;
  if FOpenTag then
  begin
    FOpenTag := False;
    if IsHtml then
      Put('></' + Name + '>')
    else
      Put('/>');
  end
  else
    Put('</' + Name + '>');
end;

{ method xhtml: the start tag as the XML serializer writes it (the
  element's own namespace declarations, ordered by prefix); a URI
  attribute escaped as in HTML }
procedure THtmlSerializer.XhtmlStartTag(const Name, Local: TLandrixXmlUtf8; I: Integer);
var
  Prefixes, Uris: TLandrixXmlUtf8Array;
  K: Integer;
  V: TLandrixXmlUtf8;
begin
  CloseTag;
  Put('<' + Name);
  if I >= 0 then
  begin
    FTree.GetDeclarations(I, Prefixes, Uris);
    SortDeclarations(Prefixes, Uris);
    for K := 0 to Integer(Length(Prefixes)) - 1 do
    begin
      if Prefixes[K] = '' then
        Put(' xmlns="')
      else
        Put(' xmlns:' + Prefixes[K] + '="');
      PutUnmapped(Uris[K]);
      Put('"');
    end;
    for K := I + 1 to I + FTree.AttributeCount[I] do
    begin
      V := FTree.ValueUtf8(K);
      { by the names in lower case, in any namespace; an element with a
        prefix is not escaped (Saxon) }
      if FEscapeUris and (FTree.NamespaceUriUtf8(K) = '') and
        InList(HtmlUri, Lower8(Local) + '+' + Lower8(FTree.LocalNameUtf8(K))) and not Pos8Byte(':', Name) then
      begin
        { an escaped URI gets no character map (Saxon) }
        V := EscapeHtmlUri(V);
        Put(' ' + FTree.NameUtf8(K) + '="');
        PutUnmapped(V);
        Put('"');
        Continue;
      end;
      Put(' ');
      PutAttr(FTree.NameUtf8(K), V);
    end;
  end;
  FOpenTag := True;
end;

{ method xhtml: an empty XHTML element of XHTML 1.0 as <br />, any other
  empty element with an end tag }
procedure THtmlSerializer.XhtmlEndTag(const Name, Local: TLandrixXmlUtf8; XhtmlElement: Boolean);
begin
  if FOpenTag then
  begin
    FOpenTag := False;
    if XhtmlElement and InList(XhtmlEmpty, Local) then
      Put(' />')
    else
      Put('></' + Name + '>');
  end
  else
    Put('</' + Name + '>');
end;

{ include-content-type: <meta http-equiv="Content-Type" ...> as the first
  child of head }
procedure THtmlSerializer.ContentTypeMeta(const Prefix: TLandrixXmlUtf8; IsHtml: Boolean);
var
  Name: TLandrixXmlUtf8;
begin
  Name := 'meta';
  if Prefix <> '' then
    Name := Prefix + ':meta';
  if FIndent and not FInFormatted and not FAfterInline and (FHtmlLevel <> 0) then
    HtmlIndent;
  if FXhtml then
    XhtmlStartTag(Name, 'meta', -1)
  else
    StartTag(Name, 'meta', IsHtml, -1);
  Put(' ');
  PutAttr('http-equiv', 'Content-Type');
  Put(' ');
  PutAttr('content', FMediaType + '; charset=' + FEncoding);
  if FXhtml then
    XhtmlEndTag(Name, 'meta', True)
  else
    EndTag(Name, 'meta', IsHtml);
  FSameLine := False;
  FAfterEndElement := True;
  FAfterInline := False;
end;

procedure THtmlSerializer.HtmlNode(I: Integer);
var
  C, K, Flags: Integer;
  Name, Local, Exact, V: TLandrixXmlUtf8;
  IsHtml, IsInline, Formatted, Skip, Meta: Boolean;
begin
  case FTree.Kind[I] of
    xnkDocument:
      begin
        C := FTree.FirstChild(I);
        while C >= 0 do
        begin
          HtmlNode(C);
          C := FTree.NextSibling[C];
        end;
      end;
    xnkElement:
      begin
        Name := FTree.NameUtf8(I);
        if (FTree.NamespaceUriUtf8(I) = XhtmlNamespace) and not FXhtml then
          Name := FTree.LocalNameUtf8(I);
        Local := Lower8(FTree.LocalNameUtf8(I));
        IsHtml := (FTree.NamespaceUriUtf8(I) = '') or (FTree.NamespaceUriUtf8(I) = XhtmlNamespace);
        { xhtml: the content type only in an XHTML head }
        Meta := FContentType and (not FXhtml or (FTree.NamespaceUriUtf8(I) = XhtmlNamespace));
        { xhtml: names as they are (Saxon: HEAD is no head, BR no br); the
          indentation still by the lower case names }
        Exact := Local;
        if FXhtml then
          Exact := FTree.LocalNameUtf8(I);
        { the meta elements of head the content type replaces (xhtml: of a
          head in the XHTML namespace) }
        if Meta and (Exact = 'meta') and (FTree.Parent[I] >= 0) and
          (not FXhtml and (Lower8(FTree.LocalNameUtf8(FTree.Parent[I])) = 'head') and
          (FTree.Parent[FTree.Parent[I]] >= 0) and
          ((FTree.Parent[FTree.Parent[FTree.Parent[I]]] < 0) or
          (FTree.Kind[FTree.Parent[FTree.Parent[FTree.Parent[I]]]] = xnkDocument)) or
          { xhtml: a head in the XHTML namespace at any depth (Saxon) }
          FXhtml and (FTree.LocalNameUtf8(FTree.Parent[I]) = 'head') and
          (FTree.NamespaceUriUtf8(FTree.Parent[I]) = XhtmlNamespace)) then
        begin
          Skip := False;
          for K := I + 1 to I + FTree.AttributeCount[I] do
          begin
            V := FTree.LocalNameUtf8(K);
            if not FXhtml then
              V := Lower8(V);
            if (FTree.NamespaceUriUtf8(K) = '') and ((V = 'charset') or (V = 'http-equiv') and
              (Lower8(Trim8Ws(FTree.ValueUtf8(K))) = 'content-type')) then
              Skip := True;
          end;
          if Skip then
            Exit;
        end;
        if not FStarted then
        begin
          FStarted := True;
          if (Local = 'html') and not FXhtml then
          begin
            Put('<!DOCTYPE HTML>');
            if FIndent then
              Put(#10);
          end;
        end;
        Flags := 0;
        if InList(HtmlInline, Local) then
          Flags := 1;
        if InList(HtmlFormatted, Local) then
          Flags := Flags or 2;
        IsInline := Flags and 1 <> 0;
        if FIndent and not IsInline and not FInFormatted and not FAfterInline and (FHtmlLevel <> 0) then
          HtmlIndent;
        if FXhtml then
          XhtmlStartTag(Name, Exact, I)
        else
          StartTag(Name, Local, IsHtml, I);
        if FIndent then
        begin
          FInFormatted := FInFormatted or (Flags and 2 <> 0);
          if FHtmlLevel >= Length(FFlags) then
            SetLength(FFlags, 2 * FHtmlLevel + 8);
          FFlags[FHtmlLevel] := Flags;
          Inc(FHtmlLevel);
          FSameLine := True;
          FAfterInline := False;
          FAfterEndElement := False;
        end;
        if Meta and (Exact = 'head') and (FTree.Parent[I] >= 0) and (FXhtml or
          (FTree.Parent[FTree.Parent[I]] < 0) or (FTree.Kind[FTree.Parent[FTree.Parent[I]]] = xnkDocument)) then
        begin
          if FXhtml then
            ContentTypeMeta(FTree.PrefixUtf8(I), True)
          else if FTree.NamespaceUriUtf8(I) = XhtmlNamespace then
            ContentTypeMeta('', True)
          else
            ContentTypeMeta(FTree.PrefixUtf8(I), IsHtml);
        end;
        C := FTree.FirstChild(I);
        while C >= 0 do
        begin
          HtmlNode(C);
          C := FTree.NextSibling[C];
        end;
        if FIndent then
        begin
          Dec(FHtmlLevel);
          Flags := FFlags[FHtmlLevel];
          IsInline := Flags and 1 <> 0;
          Formatted := Flags and 2 <> 0;
          if FAfterEndElement and not IsInline and not FAfterInline and not FSameLine and not FInFormatted then
          begin
            HtmlIndent;
            FAfterInline := False;
          end
          else
            FAfterInline := IsInline;
        end
        else
          Formatted := False;
        if FXhtml then
          XhtmlEndTag(Name, Exact, FTree.NamespaceUriUtf8(I) = XhtmlNamespace)
        else
          EndTag(Name, Local, IsHtml);
        if FIndent then
        begin
          FInFormatted := FInFormatted and not Formatted;
          FSameLine := False;
          FAfterEndElement := True;
        end;
      end;
    xnkText:
      begin
        V := FTree.ValueUtf8(I);
        { xhtml: a CDATA section (not indented) }
        if InCData(I) then
        begin
          CloseTag;
          PutCData(V);
        end
        { a text with a mapped character is not indented (Saxon) }
        else if not FIndent or FInFormatted or FHasMap and HasMapped(V) then
        begin
          CloseTag;
          HtmlText(V, False);
        end
        else
          IndentedText(V);
        if FIndent then
        begin
          FAfterInline := False;
          FAfterEndElement := False;
        end;
      end;
    xnkComment, xnkProcessingInstruction:
      begin
        if FIndent and FAfterEndElement and (FHtmlLevel > 0) and (FFlags[FHtmlLevel - 1] and 1 = 0) then
          HtmlIndent;
        CloseTag;
        if FTree.Kind[I] = xnkComment then
          Put('<!--' + FTree.ValueUtf8(I) + '-->')
        else
        begin
          V := FTree.ValueUtf8(I);
          if FXhtml then
          begin
            if V = '' then
              Put('<?' + FTree.LocalNameUtf8(I) + '?>')
            else
              Put('<?' + FTree.LocalNameUtf8(I) + ' ' + V + '?>');
          end
          else
          begin
            if Pos('>', LandrixXmlUtf8ToString(V)) > 0 then
              raise ELandrixXmlXPathError.CreateXPath('SERE0015',
                'a processing instruction in HTML must not contain ">"');
            Put('<?' + FTree.LocalNameUtf8(I) + ' ' + V + '>');
          end;
        end;
        if FIndent then
          FAfterEndElement := False;
      end;
  else
    { attributes belong to their element }
  end;
end;

function SameText8(const A, B: TLandrixXmlUtf8): Boolean;
begin
  Result := LowerCase(LandrixXmlUtf8ToString(A)) = LowerCase(LandrixXmlUtf8ToString(B));
end;

{ The text of all text nodes (method text), a character the encoding does
  not have SERE0008. }
procedure WriteText(Tree: TLandrixXmlXPathTree; Props: TXsltOutputProperties; Stream: TStream;
  MaxChar: Cardinal);
var
  I: Integer;
  S: TSerializer;
begin
  S := TSerializer.Create(Tree, Stream, False);
  try
    S.FMaxChar := MaxChar;
    S.FPlain := True;
    S.SetMap(Props);
    for I := 0 to Tree.Count - 1 do
      if Tree.Kind[I] = xnkText then
      begin
        if S.FHasMap then
          S.PutMapped(Tree.ValueUtf8(I), False)
        else
          S.Put(Tree.ValueUtf8(I));
      end;
    S.Flush;
  finally
    S.Free;
  end;
end;

procedure XsltSerialize(Tree: TLandrixXmlXPathTree; Props: TXsltOutputProperties; Stream: TStream;
  ForceUtf8: Boolean);
var
  Method, Encoding: TLandrixXmlUtf8;
  S: TSerializer;
  H: THtmlSerializer;
  E, C: Integer;
  MaxChar: Cardinal;
begin
  Method := Props.Value('method', '');
  if Method = '' then
  begin
    { html for an html root element without namespace (xhtml for one in
      the XHTML namespace, as Saxon) and only white space text before it,
      else xml }
    Method := 'xml';
    E := Tree.DocumentElement;
    if (E >= 0) and ((Tree.NamespaceUriUtf8(E) = '') and SameText8(Tree.LocalNameUtf8(E), 'html') or
      (Tree.NamespaceUriUtf8(E) = XhtmlNamespace) and (Tree.LocalNameUtf8(E) = 'html')) then
    begin
      if Tree.NamespaceUriUtf8(E) = '' then
        Method := 'html'
      else
        Method := 'xhtml';
      C := Tree.FirstChild(0);
      while (C >= 0) and (C <> E) do
      begin
        if (Tree.Kind[C] = xnkText) and not IsWhiteSpace(Tree.ValueUtf8(C)) then
          Method := 'xml';
        C := Tree.NextSibling[C];
      end;
    end;
  end;
  Encoding := Trim8Ws(Props.Value('encoding', 'UTF-8'));
  if ForceUtf8 then
    Encoding := 'UTF-8';
  MaxChar := EncodingMaxChar(Encoding);
  if MaxChar = 0 then
    raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT output: the encoding ' +
      LandrixXmlUtf8ToString(Encoding) + ' is not supported (UTF-8, US-ASCII and ISO-8859-1 only)');
  if Method = 'text' then
  begin
    WriteText(Tree, Props, Stream, MaxChar);
    Exit;
  end;
  if (Method = 'html') or (Method = 'xhtml') then
  begin
    if (Method = 'html') and Props.Has('version') and (Props.Value('version', '') <> '5') and
      (Props.Value('version', '') <> '5.0') then
      raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT output: HTML version ' +
        LandrixXmlUtf8ToString(Props.Value('version', '')) + ' is not supported (HTML5 only)');
    if (Method = 'xhtml') and (Props.Has('version') and (Props.Value('version', '') <> '1.0') or
      (Props.Value('undeclare-prefixes', 'no') = 'yes')) then
      raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT output: xhtml with a version other than 1.0 or ' +
        'undeclare-prefixes is not supported');
    H := THtmlSerializer.Create(Tree, Stream, Props.Value('indent', 'yes') = 'yes');
    try
      H.FXhtml := Method = 'xhtml';
      H.FInScript := -1000000;
      H.FEscapeUris := Props.Value('escape-uri-attributes', 'yes') = 'yes';
      H.FContentType := Props.Value('include-content-type', 'yes') = 'yes';
      H.FMediaType := Props.Value('media-type', 'text/html');
      H.FEncoding := Encoding;
      H.FMaxChar := MaxChar;
      H.SetMap(Props);
      { cdata-section-elements: not for html }
      if H.FXhtml then
        H.SetCData(Props);
      if H.FXhtml and (Props.Value('omit-xml-declaration', 'no') <> 'yes') then
      begin
        H.Put('<?xml version="1.0" encoding="' + Encoding + '"');
        if Props.Has('standalone') and (Props.Value('standalone', '') <> 'omit') then
          H.Put(' standalone="' + Props.Value('standalone', '') + '"');
        H.Put('?>');
      end;
      H.HtmlNode(0);
      H.Flush;
    finally
      H.Free;
    end;
    Exit;
  end;
  if Method <> 'xml' then
    raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT output: the method ' +
      LandrixXmlUtf8ToString(Method) + ' is not supported yet');
  if Props.Has('version') and (Props.Value('version', '') <> '1.0') or
    (Props.Value('undeclare-prefixes', 'no') = 'yes') then
    raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT output: XML 1.1 (version, undeclare-prefixes) ' +
      'is not supported');
  S := TSerializer.Create(Tree, Stream, Props.Value('indent', 'no') = 'yes');
  try
    S.FMaxChar := MaxChar;
    S.SetMap(Props);
    S.SetCData(Props);
    if Props.Value('omit-xml-declaration', 'no') <> 'yes' then
    begin
      S.Put('<?xml version="1.0" encoding="' + Encoding + '"');
      if Props.Has('standalone') and (Props.Value('standalone', '') <> 'omit') then
        S.Put(' standalone="' + Props.Value('standalone', '') + '"');
      S.Put('?>');
      S.FAfterEnd := True;
    end;
    S.Node(0);
    if S.FIndent and S.FAfterEnd then
      S.Put(#10);
    S.Flush;
  finally
    S.Free;
  end;
end;

end.
