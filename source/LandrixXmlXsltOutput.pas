{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Internal unit of the XSLT processor (LandrixXmlXslt), not part of the
  documented API: the output properties of xsl:output and the
  serialization of a result tree as Saxon HE writes it.

  Methods xml, html and text. xml escapes as Saxon does (& < > in text,
  also " and white space other than the space in attributes, carriage
  returns everywhere as character references) and writes the namespace
  declarations each element holds, ordered by prefix; indent="yes"
  indents as Saxon's indenter does, byte for byte (see
  TSerializer.Element). html writes HTML5 as Saxon's HTML emitter and
  HTML indenter do (see THtmlSerializer). The encoding is UTF-8; another
  raises xecUnsupported. }

unit LandrixXmlXsltOutput;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlXPathTree;

type
  TXsltOutputProperties = class
  private
    FNames: TLandrixXmlUtf8Array;
    FValues: TLandrixXmlUtf8Array;
  public
    procedure SetValue(const Name, AValue: TLandrixXmlUtf8);
    function Value(const Name, Default: TLandrixXmlUtf8): TLandrixXmlUtf8;
    function Has(const Name: TLandrixXmlUtf8): Boolean;
    function Clone: TXsltOutputProperties;
  end;

  TXsltOutputStatus = (xosSupported, xosUnsupported, xosUnknown, xosInvalid);

{ Whether an output property (an attribute of xsl:output, no namespace;
  AValue; true, 1, false, 0 and surrounding white space allowed for yes
  and no as in Saxon) is one this serializer does:
  unknown for a name XSLT 2.0 does not define, unsupported for one it does
  not do (other methods and encodings, doctype, character maps and so on,
  the XSLT 3.0 properties). }
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
    else if (Name = 'name') or (Name = 'use-character-maps') or (Name = 'cdata-section-elements') or
      (Name = 'doctype-public') or (Name = 'doctype-system') or (Name = 'method') and (Value <> 'xml') and
      (Value <> 'text') and (Value <> 'html') or (Name = 'encoding') and
      (LowerCase(LandrixXmlUtf8ToString(Value)) <> 'utf-8') or
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
    procedure Put(const S: TLandrixXmlUtf8);
    procedure Flush;
    procedure Spaces(N: Integer);
    procedure Indent;
    procedure FlushPending;
    procedure PutText(const S: TLandrixXmlUtf8);
    procedure PutAttributeValue(const S: TLandrixXmlUtf8);
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
  SetLength(FBuffer, 65536);
end;

procedure TSerializer.Flush;
begin
  if FLength > 0 then
    FStream.WriteBuffer(PAnsiChar(FBuffer)^, FLength);
  FLength := 0;
end;

procedure TSerializer.Put(const S: TLandrixXmlUtf8);
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

procedure TSerializer.PutText(const S: TLandrixXmlUtf8);
var
  I, Start: Integer;
  R: TLandrixXmlUtf8;
begin
  Start := 1;
  for I := 1 to Length(S) do
  begin
    case S[I] of
      '<': R := '&lt;';
      '>': R := '&gt;';
      '&': R := '&amp;';
      #13: R := '&#xD;';
    else
      Continue;
    end;
    Put(Copy(S, Start, I - Start));
    Put(R);
    Start := I + 1;
  end;
  Put(Copy(S, Start, Length(S) - Start + 1));
end;

procedure TSerializer.PutAttributeValue(const S: TLandrixXmlUtf8);
var
  I, Start: Integer;
  R: TLandrixXmlUtf8;
begin
  Start := 1;
  for I := 1 to Length(S) do
  begin
    case S[I] of
      '<': R := '&lt;';
      '>': R := '&gt;';
      '&': R := '&amp;';
      '"': R := '&#34;';
      #9: R := '&#x9;';
      #10: R := '&#xA;';
      #13: R := '&#xD;';
    else
      Continue;
    end;
    Put(Copy(S, Start, I - Start));
    Put(R);
    Start := I + 1;
  end;
  Put(Copy(S, Start, Length(S) - Start + 1));
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
        Inc(Len, JavaLength(FTree.LocalNameUtf8(K)) + JavaLength(FTree.ValueUtf8(K)) + 4);
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
    PutAttributeValue(Uris[K]);
    Put('"');
  end;
  for K := I + 1 to I + FTree.AttributeCount[I] do
  begin
    Separator;
    Put(FTree.NameUtf8(K) + '="');
    PutAttributeValue(FTree.ValueUtf8(K));
    Put('"');
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
        if FIndent then
        begin
          if (FSuppressedAt < 0) and IsWhiteSpace(V) then
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

type
  { Writes a tree as Saxon HE's HTML5 serializer and HTML indenter do. }
  THtmlSerializer = class(TSerializer)
  private
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
    { the default namespace of the output per open element }
    FDefaults: TLandrixXmlUtf8Array;
    { per output element: the prefixes of its XHTML attributes }
    FXhtmlPrefixes: TLandrixXmlUtf8Array;
    FNsDepth: Integer;
    procedure CloseTag;
    procedure HtmlIndent;
    procedure HtmlText(const S: TLandrixXmlUtf8; Attribute: Boolean);
    procedure IndentedText(const S: TLandrixXmlUtf8);
    procedure StartTag(const Name, Local: TLandrixXmlUtf8; IsHtml: Boolean; I: Integer);
    procedure EndTag(const Name, Local: TLandrixXmlUtf8; IsHtml: Boolean);
    procedure ContentTypeMeta(const Prefix: TLandrixXmlUtf8; IsHtml: Boolean);
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
  Drop: Boolean;
begin
  if FInScript > 0 then
  begin
    Put(S);
    Exit;
  end;
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
      HtmlText(Uris[K], True);
      Put('"');
    end;
    for K := I + 1 to I + FTree.AttributeCount[I] do
    begin
      AName := FTree.NameUtf8(K);
      ALocal := Lower8(FTree.LocalNameUtf8(K));
      V := FTree.ValueUtf8(K);
      if IsHtml and (FTree.NamespaceUriUtf8(K) = '') and (Lower8(V) = ALocal) and
        (InList(HtmlBoolean, Local + '+' + ALocal) or InList(HtmlBoolean, '*+' + ALocal)) then
      begin
        Put(' ' + AName);
        Continue;
      end;
      { by the names of an element without a prefix, in any namespace
        (Saxon) }
      if FEscapeUris and (FTree.NamespaceUriUtf8(K) = '') and InList(HtmlUri, Local + '+' + ALocal) and
        not Pos8Byte(':', FTree.NameUtf8(I)) then
        V := EscapeHtmlUri(V);
      Put(' ' + AName + '="');
      HtmlText(V, True);
      Put('"');
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
  StartTag(Name, 'meta', IsHtml, -1);
  Put(' http-equiv="Content-Type" content="');
  HtmlText(FMediaType + '; charset=UTF-8', True);
  Put('"');
  EndTag(Name, 'meta', IsHtml);
  FSameLine := False;
  FAfterEndElement := True;
  FAfterInline := False;
end;

procedure THtmlSerializer.HtmlNode(I: Integer);
var
  C, K, Flags: Integer;
  Name, Local, V: TLandrixXmlUtf8;
  IsHtml, IsInline, Formatted, Skip: Boolean;
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
        if FTree.NamespaceUriUtf8(I) = XhtmlNamespace then
          Name := FTree.LocalNameUtf8(I);
        Local := Lower8(FTree.LocalNameUtf8(I));
        IsHtml := (FTree.NamespaceUriUtf8(I) = '') or (FTree.NamespaceUriUtf8(I) = XhtmlNamespace);
        { the meta elements of head the content type replaces }
        if FContentType and (Local = 'meta') and (FTree.Parent[I] >= 0) and
          (Lower8(FTree.LocalNameUtf8(FTree.Parent[I])) = 'head') and (FTree.Parent[FTree.Parent[I]] >= 0) and
          ((FTree.Parent[FTree.Parent[FTree.Parent[I]]] < 0) or
          (FTree.Kind[FTree.Parent[FTree.Parent[FTree.Parent[I]]]] = xnkDocument)) then
        begin
          Skip := False;
          for K := I + 1 to I + FTree.AttributeCount[I] do
            if (FTree.NamespaceUriUtf8(K) = '') and ((Lower8(FTree.LocalNameUtf8(K)) = 'charset') or
              (Lower8(FTree.LocalNameUtf8(K)) = 'http-equiv') and
              (Lower8(Trim8Ws(FTree.ValueUtf8(K))) = 'content-type')) then
              Skip := True;
          if Skip then
            Exit;
        end;
        if not FStarted then
        begin
          FStarted := True;
          if Local = 'html' then
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
        if FContentType and (Local = 'head') and (FTree.Parent[I] >= 0) and
          ((FTree.Parent[FTree.Parent[I]] < 0) or (FTree.Kind[FTree.Parent[FTree.Parent[I]]] = xnkDocument)) then
        begin
          if FTree.NamespaceUriUtf8(I) = XhtmlNamespace then
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
        if not FIndent or FInFormatted then
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
          if Pos('>', LandrixXmlUtf8ToString(V)) > 0 then
            raise ELandrixXmlXPathError.CreateXPath('SERE0015',
              'a processing instruction in HTML must not contain ">"');
          Put('<?' + FTree.LocalNameUtf8(I) + ' ' + V + '>');
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

{ The text of all text nodes (method text). }
procedure WriteText(Tree: TLandrixXmlXPathTree; Stream: TStream);
var
  I: Integer;
  S: TLandrixXmlUtf8;
begin
  for I := 0 to Tree.Count - 1 do
    if Tree.Kind[I] = xnkText then
    begin
      S := Tree.ValueUtf8(I);
      if S <> '' then
        Stream.WriteBuffer(PAnsiChar(S)^, Length(S));
    end;
end;

procedure XsltSerialize(Tree: TLandrixXmlXPathTree; Props: TXsltOutputProperties; Stream: TStream;
  ForceUtf8: Boolean);
var
  Method, Encoding: TLandrixXmlUtf8;
  S: TSerializer;
  H: THtmlSerializer;
  E, C: Integer;
begin
  Method := Props.Value('method', '');
  if Method = '' then
  begin
    { html for an html root element without namespace and only white space
      text before it, else xml }
    Method := 'xml';
    E := Tree.DocumentElement;
    if (E >= 0) and (Tree.NamespaceUriUtf8(E) = '') and SameText8(Tree.LocalNameUtf8(E), 'html') then
    begin
      Method := 'html';
      C := Tree.FirstChild(0);
      while (C >= 0) and (C <> E) do
      begin
        if (Tree.Kind[C] = xnkText) and not IsWhiteSpace(Tree.ValueUtf8(C)) then
          Method := 'xml';
        C := Tree.NextSibling[C];
      end;
    end;
  end;
  Encoding := Props.Value('encoding', 'UTF-8');
  if ForceUtf8 then
    Encoding := 'UTF-8';
  if not SameText8(Encoding, 'UTF-8') then
    raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT output: the encoding ' +
      LandrixXmlUtf8ToString(Encoding) + ' is not supported (UTF-8 only)');
  if Method = 'text' then
  begin
    WriteText(Tree, Stream);
    Exit;
  end;
  if Method = 'html' then
  begin
    if Props.Has('version') and (Props.Value('version', '') <> '5') and (Props.Value('version', '') <> '5.0') then
      raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT output: HTML version ' +
        LandrixXmlUtf8ToString(Props.Value('version', '')) + ' is not supported (HTML5 only)');
    H := THtmlSerializer.Create(Tree, Stream, Props.Value('indent', 'yes') = 'yes');
    try
      H.FInScript := -1000000;
      H.FEscapeUris := Props.Value('escape-uri-attributes', 'yes') = 'yes';
      H.FContentType := Props.Value('include-content-type', 'yes') = 'yes';
      H.FMediaType := Props.Value('media-type', 'text/html');
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
