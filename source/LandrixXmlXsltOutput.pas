{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Internal unit of the XSLT processor (LandrixXmlXslt), not part of the
  documented API: the output properties of xsl:output and the
  serialization of a result tree as Saxon HE writes it.

  Methods xml and text. xml escapes as Saxon does (& < > in text, also "
  and white space other than the space in attributes, carriage returns
  everywhere as character references) and writes the namespace
  declarations each element holds; indent="yes" puts every element of
  element-only content on a new line, three spaces per level, and drops
  white space text there (equal to Saxon's after parsing, not byte by
  byte). The encoding is UTF-8; another raises xecUnsupported. }

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
    procedure SetValue(const Name, Value: TLandrixXmlUtf8);
    function Value(const Name, Default: TLandrixXmlUtf8): TLandrixXmlUtf8;
    function Has(const Name: TLandrixXmlUtf8): Boolean;
    function Clone: TXsltOutputProperties;
  end;

  TXsltOutputStatus = (xosSupported, xosUnsupported, xosUnknown);

{ Whether an output property (an attribute of xsl:output, no namespace;
  Value without surrounding white space) is one this serializer does:
  unknown for a name XSLT 2.0 does not define, unsupported for one it does
  not do (other methods and encodings, doctype, character maps and so on,
  the XSLT 3.0 properties). }
function XsltOutputPropertyStatus(const Name, Value: TLandrixXmlUtf8): TXsltOutputStatus;

{ Writes Tree (a document) to Stream; ForceUtf8: UTF-8 whatever the
  encoding property says (the declaration then names UTF-8). }
procedure XsltSerialize(Tree: TLandrixXmlXPathTree; Props: TXsltOutputProperties; Stream: TStream;
  ForceUtf8: Boolean);

implementation

function XsltOutputPropertyStatus(const Name, Value: TLandrixXmlUtf8): TXsltOutputStatus;
begin
  Result := xosSupported;
  if (Name = 'method') or (Name = 'version') or (Name = 'encoding') or (Name = 'omit-xml-declaration') or
    (Name = 'standalone') or (Name = 'doctype-public') or (Name = 'doctype-system') or
    (Name = 'cdata-section-elements') or (Name = 'indent') or (Name = 'media-type') or
    (Name = 'byte-order-mark') or (Name = 'escape-uri-attributes') or (Name = 'include-content-type') or
    (Name = 'normalization-form') or (Name = 'undeclare-prefixes') or (Name = 'use-character-maps') or
    (Name = 'name') then
  begin
    if (Name = 'name') or (Name = 'use-character-maps') or (Name = 'cdata-section-elements') or
      (Name = 'doctype-public') or (Name = 'doctype-system') or (Name = 'method') and (Value <> 'xml') and
      (Value <> 'text') or (Name = 'encoding') and (LowerCase(LandrixXmlUtf8ToString(Value)) <> 'utf-8') or
      (Name = 'byte-order-mark') and (Value = 'yes') or (Name = 'undeclare-prefixes') and (Value = 'yes') or
      (Name = 'version') and (Value <> '1.0') or (Name = 'normalization-form') and (Value <> 'none') or
      (Name = 'escape-uri-attributes') or (Name = 'include-content-type') then
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

procedure TXsltOutputProperties.SetValue(const Name, Value: TLandrixXmlUtf8);
var
  I: Integer;
begin
  for I := 0 to Integer(Length(FNames)) - 1 do
    if FNames[I] = Name then
    begin
      FValues[I] := Value;
      Exit;
    end;
  I := Integer(Length(FNames));
  SetLength(FNames, I + 1);
  SetLength(FValues, I + 1);
  FNames[I] := Name;
  FValues[I] := Value;
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
  E: Integer;
begin
  Method := Props.Value('method', '');
  if Method = '' then
  begin
    { html for an html root element without namespace, else xml }
    Method := 'xml';
    E := Tree.DocumentElement;
    if (E >= 0) and (Tree.NamespaceUriUtf8(E) = '') and SameText8(Tree.LocalNameUtf8(E), 'html') then
      Method := 'html';
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
  if Method <> 'xml' then
    raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT output: the method ' +
      LandrixXmlUtf8ToString(Method) + ' is not supported yet');
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
