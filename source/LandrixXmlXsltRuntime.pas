{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Internal unit of the XSLT processor (LandrixXmlXslt), not part of the
  documented API: one run of a compiled stylesheet
  (LandrixXmlXsltCompiler).

  Instructions write to a receiver. A tree receiver builds a tree
  (element content: atomic values become text, separated by a space when
  adjacent; nodes are copied; attributes go to the element just started,
  where a later one replaces an earlier one with the same name), fixing
  the namespaces when an element's start is complete. A sequence
  receiver collects the items of a sequence constructor (xsl:variable
  with "as", template results with "as"): nodes it constructs become
  trees without document node, added to the evaluator with AddTree.

  The principal result is built as a tree; LandrixXmlXsltOutput
  serializes it. Templates and stylesheet functions run in frames of
  their own (PushFrame). XPath errors escaping an instruction get its
  module and line. }

unit LandrixXmlXsltRuntime;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  Contnrs,
  LandrixXmlBase,
  LandrixXmlXsdTypes,
  LandrixXmlXPathTree,
  LandrixXmlXPath,
  LandrixXmlXPathEval,
  LandrixXmlXslt,
  LandrixXmlXsltCompiler,
  LandrixXmlXPathFormat;

type
  TXsltRunSettings = class
  public
    ParamNames: TLandrixXmlUtf8Array;
    ParamKinds: array of Integer;
    ParamValues: TLandrixXmlUtf8Array;
    ParamTrees: array of TLandrixXmlXPathTree;
    InitialMode: TLandrixXmlUtf8;
    InitialTemplate: TLandrixXmlUtf8;
    Resolver: TLandrixXmlXsltResolver;
    ImplicitTimeZone: Integer;
    HasClock: Boolean;
    Clock: TLandrixXmlXsdDateTime;
    MaxDepth: Integer;
    MaxTemplateDepth: Integer;
    MaxStackBytes: Integer;
    { TLandrixXmlXsltMessage, owned by the transformer }
    Messages: TObjectList;
    { xsl:result-document: the base output URI, the list the secondary
      results (TLandrixXmlXsltResultDocument) go to after a successful
      run (owned by the transformer), and the output properties of an
      xsl:result-document that made the principal result
      (TXsltOutputProperties for the caller to free; nil if none) }
    BaseOutputUri: TLandrixXmlUtf8;
    ResultDocuments: TObjectList;
    PrincipalProperties: TObject;
    { disable-output-escaping: the raw parts of the principal result are
      added to this TXsltOutputProperties (owned by the caller; nil: they
      are ignored) }
    PrincipalRaw: TObject;
    procedure AddParameter(const Name: TLandrixXmlUtf8; Kind: Integer; const Value: TLandrixXmlUtf8;
      Tree: TLandrixXmlXPathTree);
  end;

{ Whether S has a URI scheme (RFC 3986: a letter, then letters, digits,
  + - .; at least two characters, so that C:\x is no URI). }
function XsltHasUriScheme(const S: TLandrixXmlUtf8): Boolean;

{ Runs Compiled on Source (nil: an empty document) into Target. }
procedure XsltRun(Compiled: TObject; Settings: TXsltRunSettings; Source, Target: TLandrixXmlXPathTree);

implementation

uses
  LandrixXmlReader,
  LandrixXmlUnicode,
  LandrixXmlRegex,
  LandrixXmlXsltOutput;

type
  TRun = class;

  TReceiver = class
  protected
    FRun: TRun;
  public
    constructor Create(ARun: TRun);
    procedure StartElement(const Uri, Prefix, Local: TLandrixXmlUtf8); virtual; abstract;
    procedure NamespaceNode(const Prefix, Uri: TLandrixXmlUtf8); virtual; abstract;
    procedure Attribute(const Uri, Prefix, Local, Value: TLandrixXmlUtf8); virtual; abstract;
    procedure Characters(const S: TLandrixXmlUtf8); virtual; abstract;
    { text with disable-output-escaping: as Characters but in a final
      result tree }
    procedure RawCharacters(const S: TLandrixXmlUtf8); virtual;
    procedure Comment(const S: TLandrixXmlUtf8); virtual; abstract;
    procedure ProcessingInstruction(const Target, S: TLandrixXmlUtf8); virtual; abstract;
    procedure EndElement; virtual; abstract;
    { an item of a sequence (xsl:sequence, xsl:copy-of: Copy) }
    procedure Item(const It: TLandrixXmlXPathItem; Copy: Boolean);
    procedure AddItem(const It: TLandrixXmlXPathItem); virtual; abstract;
    { a copy of a node (in a tree any node is copied: AddItem) }
    procedure CopyItem(const It: TLandrixXmlXPathItem); virtual;
    { the namespaces a node added now would inherit (the default one with
      the prefix '', an empty URI for none) }
    procedure InheritedNamespaces(var Prefixes, Uris: TLandrixXmlUtf8Array); virtual;
    { a namespace node declared even where the scope has it already }
    procedure ForceNamespace(const Prefix, Uri: TLandrixXmlUtf8); virtual;
  end;

  { builds Tree (BeginBuild called by the creator) }
  TTreeReceiver = class(TReceiver)
  private
    FTree: TLandrixXmlXPathTree;
    FPending: Boolean;
    FUri, FPrefix, FLocal: TLandrixXmlUtf8;
    FNsPrefixes, FNsUris: TLandrixXmlUtf8Array;
    FAttrUris, FAttrPrefixes, FAttrLocals, FAttrValues: TLandrixXmlUtf8Array;
    FAttrCount: Integer;
    { an element with many attributes: a hash table of the expanded names
      for the duplicate check (open addressing, -1 = free); FAttrHashed =
      the attributes entered, 0 = no table yet }
    FAttrSlots: array of Integer;
    FAttrHashed: Integer;
    { the salted hash of the last attribute URI, by its string: the
      attributes of a copied element share one string per URI }
    FHashedUri: TLandrixXmlUtf8;
    FHashedUriHash: Cardinal;
    { the namespaces in scope: bindings and the count per open element }
    FScopePrefixes, FScopeUris: TLandrixXmlUtf8Array;
    FScopeCount: Integer;
    FMarks: array of Integer;
    FDepth: Integer;
    FLastAtomic: Boolean;
    { something was written (a node or an atomic value, also an empty
      string): a principal result besides xsl:result-document is XTDE1490 }
    FWritten: Boolean;
    FDocument: Boolean;
    { an attribute at the top is its value as text (xsl:message) }
    FAttributesAsText: Boolean;
    { a final result tree: where its raw text parts go (nil for a
      temporary tree: disable-output-escaping is ignored) }
    FRawProps: TXsltOutputProperties;
    { xsl:document: raw text is not supported (Saxon keeps it raw);
      xsl:message: a raw text item is plain text (only the string counts) }
    FRawFails: Boolean;
    FRawIgnored: Boolean;
    { the pending element's declarations kept although the scope has them
      (ForceNamespace) }
    FForced: TLandrixXmlUtf8Array;
    function IsForced(const Prefix: TLandrixXmlUtf8): Boolean;
    procedure Flush;
    function FreePrefix(const Prefix, Uri: TLandrixXmlUtf8; First: Integer): TLandrixXmlUtf8;
    function Taken(const Prefix, Uri: TLandrixXmlUtf8): Boolean;
    function AttrPrefixFree(const Prefix, Uri: TLandrixXmlUtf8; Index: Integer): Boolean;
    function Bound(const Prefix: TLandrixXmlUtf8; out Uri: TLandrixXmlUtf8): Boolean;
    function InScope(const Prefix: TLandrixXmlUtf8; out Uri: TLandrixXmlUtf8): Boolean;
    procedure Declare(const Prefix, Uri: TLandrixXmlUtf8);
    procedure Content;
    function AttrHash(const Uri, Local: TLandrixXmlUtf8): Cardinal;
    function FindAttr(const Uri, Local: TLandrixXmlUtf8): Integer;
    procedure IndexAttrs;
  public
    constructor Create(ARun: TRun; Tree: TLandrixXmlXPathTree; Document: Boolean);
    procedure StartElement(const Uri, Prefix, Local: TLandrixXmlUtf8); override;
    procedure NamespaceNode(const Prefix, Uri: TLandrixXmlUtf8); override;
    procedure Attribute(const Uri, Prefix, Local, Value: TLandrixXmlUtf8); override;
    procedure Characters(const S: TLandrixXmlUtf8); override;
    procedure RawCharacters(const S: TLandrixXmlUtf8); override;
    procedure Comment(const S: TLandrixXmlUtf8); override;
    procedure ProcessingInstruction(const Target, S: TLandrixXmlUtf8); override;
    procedure EndElement; override;
    procedure AddItem(const It: TLandrixXmlXPathItem); override;
    procedure CopyItem(const It: TLandrixXmlXPathItem); override;
    procedure InheritedNamespaces(var Prefixes, Uris: TLandrixXmlUtf8Array); override;
    procedure ForceNamespace(const Prefix, Uri: TLandrixXmlUtf8); override;
    { completes the tree (EndBuild) }
    procedure Finish;
    property Depth: Integer read FDepth;
  end;

  TSequenceReceiver = class(TReceiver)
  private
    FItems: TLandrixXmlXPathSequence;
    { the base URI of the next node of its own (xsl:copy: the original's;
      FHasNextBase), else BaseUri }
    FNextBase: TLandrixXmlUtf8;
    FHasNextBase: Boolean;
    FTreeBase: TLandrixXmlUtf8;
    { the static base URI of the xsl:copy-of whose items are copied }
    CopyBase: TLandrixXmlUtf8;
    { the base URI of the trees of the nodes made at the top (the static
      base URI of the instruction that makes the sequence; set by TRun) }
    BaseUri: TLandrixXmlUtf8;
    FInner: TTreeReceiver;
    FInnerTree: TLandrixXmlXPathTree;
    procedure StartNode;
    procedure EndNode;
  public
    constructor Create(ARun: TRun);
    destructor Destroy; override;
    procedure StartElement(const Uri, Prefix, Local: TLandrixXmlUtf8); override;
    procedure NamespaceNode(const Prefix, Uri: TLandrixXmlUtf8); override;
    procedure Attribute(const Uri, Prefix, Local, Value: TLandrixXmlUtf8); override;
    procedure Characters(const S: TLandrixXmlUtf8); override;
    procedure RawCharacters(const S: TLandrixXmlUtf8); override;
    procedure Comment(const S: TLandrixXmlUtf8); override;
    procedure ProcessingInstruction(const Target, S: TLandrixXmlUtf8); override;
    procedure EndElement; override;
    procedure AddItem(const It: TLandrixXmlXPathItem); override;
    procedure CopyItem(const It: TLandrixXmlXPathItem); override;
    procedure InheritedNamespaces(var Prefixes, Uris: TLandrixXmlUtf8Array); override;
    procedure ForceNamespace(const Prefix, Uri: TLandrixXmlUtf8); override;
    procedure SetNextBase(const Uri: TLandrixXmlUtf8);
    property Items: TLandrixXmlXPathSequence read FItems;
  end;

  { a parameter value supplied to a template }
  TSupplied = record
    Name: TLandrixXmlUtf8;
    Value: TLandrixXmlXPathSequence;
  end;
  TSuppliedArray = array of TSupplied;
  TSequenceArray = array of TLandrixXmlXPathSequence;
  { the order of sorted items: their indexes }
  TSortOrder = array of Integer;

  TRun = class
  private
    FC: TXsltCompiled;
    FSettings: TXsltRunSettings;
    FEvaluator: TLandrixXmlXPathEvaluator;
    FSource: TLandrixXmlXPathTree;
    FEmpty: TLandrixXmlXPathTree;
    { the source without the white space xsl:strip-space removes (owned),
      and the source as given (a parameter may be that tree) }
    FStripped: TLandrixXmlXPathTree;
    FGivenSource: TLandrixXmlXPathTree;
    FTrees: TObjectList;
    FFunctions: TList;
    FDefs: TObjectList;
    FTemplateDepth: Integer;
    { the stack address at the start of the run (MaxStackBytes) }
    FStackBase: Pointer;
    FParamExprs: TObjectList;
    { current(): an atomic item of the instruction (a node: CurrentNode) }
    FCurrent: TLandrixXmlXPathSequence;
    FResolver: TLandrixXmlXsltResolver;
    FOwnResolver: Boolean;
    { documents read by doc() and document(): URI and node number }
    FDocUris: TStringList;
    FDocNodes: array of Integer;
    FTrue, FFalse: TLandrixXmlXPathExpression;
    { xsl:number value: round(number(.)) as an integer, -1 for NaN }
    FRoundExpr: TLandrixXmlXPathExpression;
    { number(.), to compare numeric keys }
    FNumberExpr: TLandrixXmlXPathExpression;
    { xs:double(.): a function argument of type xs:double }
    FDoubleExpr: TLandrixXmlXPathExpression;
    { . * 100 and . * 1000 for a double in a percent or per-mille picture }
    FTimes100Expr, FTimes1000Expr: TLandrixXmlXPathExpression;
    { the current group and its key (xsl:for-each-group); FGroupActive
      False where there is none (XTDE1061) }
    FGroup: TLandrixXmlXPathSequence;
    FGroupKey: TLandrixXmlXPathSequence;
    FGroupActive: Boolean;
    FGroupLazyDepth: Integer;
    { group-by or group-adjacent: there is a grouping key }
    FGroupHasKey: Boolean;
    { regex-group(): the string being analyzed and the positions of the
      current match and its groups (code points; see
      TLandrixXmlRegex.Analyze), FRegexActive False where there is none }
    FRegexText: TLandrixXmlCodePoints;
    FRegexGroups: TLandrixXmlCodePoints;
    FRegexActive: Boolean;
    { the current template rule (xsl:next-match, xsl:apply-imports); nil
      where there is none (XTDE0560): in xsl:for-each,
      xsl:for-each-group, xsl:analyze-string, sort keys, keys, functions
      and global variables (XSLT 2.0, 5.4.4) }
    FRule: TXsltRule;
    { the lazy depth of the evaluator in the match: a global variable
      evaluated lazily inside it sees no captured substrings }
    FRegexLazyDepth: Integer;
    { generate-id(): per tree number the tree and the numbers of its nodes }
    FIdTrees: array of TLandrixXmlXPathTree;
    FIdNumbers: array of TSortOrder;
    { the canonical form of a QName, xs:dateTime or xs:time key }
    FKeyNormExpr: TLandrixXmlXPathExpression;
    { the indexes of xsl:key built so far (TKeyIndex) }
    FKeyIndexes: TObjectList;
    { xsl:result-document: in a temporary output state (XTDE1480: inside
      variables, parameters, attributes, comments, processing
      instructions, value-of, messages, sort keys and functions); the
      secondary results so far (owned until the run succeeds) and their
      URIs; the principal result an xsl:result-document made (owned) and
      its properties; the tree and receiver of the implicit principal
      result }
    FTemporary: Boolean;
    { set by HostCompatible for the Host call it makes with the converted
      arguments }
    FArgumentsConverted: Boolean;
    { disable-output-escaping: the text nodes made at the top of a sequence
      (xsl:function, a template with as) from raw text, in the order made;
      written raw when they are added to a final result tree (as Saxon;
      not when copied with xsl:copy-of) }
    FRawTexts: array of Integer;
    FRawTextCount: Integer;
    { xsl:document: the next BodyDocument rejects raw text }
    FDocumentRaw: Boolean;
    { xsl:copy-of copy-namespaces="no": CopyNode copies no namespace nodes
      (the receiver declares those the names need) }
    FNoNamespaces: Boolean;
    { the tunnel parameters the current template received (passed on by
      xsl:apply-templates, xsl:call-template, xsl:next-match,
      xsl:apply-imports and the built-in rules; none in functions and
      global variables) }
    FTunnel: TSuppliedArray;
    FResults: TObjectList;
    FResultUris: TStringList;
    FPrincipal: TLandrixXmlXPathTree;
    FPrincipalProps: TXsltOutputProperties;
    FImplicit: TLandrixXmlXPathTree;
    FImplicitReceiver: TTreeReceiver;
    { per module: static-base-uri() and resolve-uri(.) with its URI }
    FBaseExprs: TObjectList;
    { xs:dateTime?, xs:date?, xs:time? (the first argument of the format
      functions) }
    FDateTypes: array[TXPathDateKind] of TLandrixXmlXPathSequenceType;
    FStringType, FOptionalStringType, FIntegerType: TLandrixXmlXPathSequenceType;
    function FormatDate(Kind: TXPathDateKind; const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function AtomKey(const It: TLandrixXmlXPathItem): TLandrixXmlUtf8;
    function ExactNumber(const It: TLandrixXmlXPathItem): TLandrixXmlUtf8;
    { a declaration of K in backwards compatible mode: all values of K
      are compared as strings (XSLT 2.0 section 16.3.1) }
    function KeyStrings(K: TXsltKey): Boolean;
    function KeyFunction(const Args: array of TLandrixXmlXPathSequence;
      const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
    function KeyIndex(K: TXsltKey; Root: Integer): TObject;
    function GenerateId(Node: Integer): TLandrixXmlUtf8;
    function Availability(Evaluator: TLandrixXmlXPathEvaluator; Kind: Integer;
      const NameArg, ArityArg: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function FormatNumber(const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function UnparsedText(Kind: Integer; const Base: TLandrixXmlUtf8;
      const HrefArg, EncodingArg: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function StrippedCopy(Tree: TLandrixXmlXPathTree): TLandrixXmlXPathTree;
    procedure DoForEachGroup(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      R: TReceiver);
    function SortOrder(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      const Items: TLandrixXmlXPathSequence; const Groups, GroupKeys: TSequenceArray;
      HasKey: Boolean): TSortOrder;
    function Sorted(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      const S: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    procedure DoPerformSort(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      R: TReceiver);
    procedure DoAnalyzeString(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      R: TReceiver);
    function RegexGroup(const Arg: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function PatternMatches(Expr: TLandrixXmlXPathExpression; Node: Integer; Relative: Boolean): Boolean;
    function OpenResource(Kind: TLandrixXmlXsltResourceKind; const Base, Href: TLandrixXmlUtf8;
      out Uri: TLandrixXmlUtf8; out Content: TStream): Boolean;
    function LoadDocument(const Href, Base: TLandrixXmlUtf8; Available: Boolean): Integer;
    function DocFunction(Kind, Module: Integer; const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function Host(Evaluator: TLandrixXmlXPathEvaluator; Def: TLandrixXmlXPathFunctionDef;
      const Args: array of TLandrixXmlXPathSequence; const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
    { Host for a caller in XPath 1.0 compatibility mode: the arguments
      converted, then Host; FirstStringSeq and FirstNumberSeq: fn:string
      and fn:number of the first item }
    function FirstStringSeq(const S: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function FirstNumberSeq(const S: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function HostCompatible(Evaluator: TLandrixXmlXPathEvaluator; Def: TLandrixXmlXPathFunctionDef;
      const Args: array of TLandrixXmlXPathSequence; const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
    procedure Fail(Instr: TXsltInstr; const Code, Msg: string);
    procedure CheckCollation(Instr: TXsltInstr; const Uri: TLandrixXmlUtf8; const Code: string);
    function Eval(Instr: TXsltInstr; Expr: TLandrixXmlXPathExpression;
      const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
    function SimpleContent(const S: TLandrixXmlXPathSequence; const Separator: TLandrixXmlUtf8): TLandrixXmlUtf8;
    function EvalString(Instr: TXsltInstr; Expr: TLandrixXmlXPathExpression;
      const Focus: TLandrixXmlXPathFocus; const Separator: TLandrixXmlUtf8): TLandrixXmlUtf8;
    { the string value of the first item of Expr's value ('' for none):
      xsl:value-of and attribute value templates in backwards compatible
      mode }
    function FirstString(Instr: TXsltInstr; Expr: TLandrixXmlXPathExpression;
      const Focus: TLandrixXmlXPathFocus): TLandrixXmlUtf8;
    function EvalAvt(Instr: TXsltInstr; Avt: TXsltAvt; const Focus: TLandrixXmlXPathFocus): TLandrixXmlUtf8;
    function BodyString(Body: TObjectList; const Focus: TLandrixXmlXPathFocus;
      const Mode: TXsltMode; const Separator: TLandrixXmlUtf8): TLandrixXmlUtf8;
    function TemporarySequence(Body: TObjectList; const Focus: TLandrixXmlXPathFocus;
      const Mode: TXsltMode): TLandrixXmlXPathSequence;
    function BodySequence(Body: TObjectList; const BaseUri: TLandrixXmlUtf8; const Focus: TLandrixXmlXPathFocus;
      const Mode: TXsltMode): TLandrixXmlXPathSequence;
    function ContentDocument(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus;
      const Mode: TXsltMode): TLandrixXmlXPathSequence;
    function BodyDocument(Body: TObjectList; const BaseUri: TLandrixXmlUtf8; const Focus: TLandrixXmlXPathFocus;
      const Mode: TXsltMode): TLandrixXmlXPathSequence;
    function VariableValue(Instr: TXsltInstr; const BaseUri: TLandrixXmlUtf8; Select: TLandrixXmlXPathExpression;
      Body: TObjectList;
      HasAs: Boolean; const AsType: TLandrixXmlXPathSequenceType; const Name: TLandrixXmlUtf8;
      const Focus: TLandrixXmlXPathFocus; const Mode: TXsltMode): TLandrixXmlXPathSequence;
    procedure Exec(Body: TObjectList; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure ExecInstr(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure LiteralElement(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      R: TReceiver);
    procedure ComputedName(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Element: Boolean;
      out Uri, Prefix, Local: TLandrixXmlUtf8);
    procedure CopyInstr(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure ExecCore(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure DoText(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; R: TReceiver);
    procedure DoValueOf(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure DoVariable(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode);
    function Test(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus): Boolean;
    function ChosenBody(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus): TObjectList;
    procedure DoForEach(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure DoSequence(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; R: TReceiver);
    procedure DoElement(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure DoAttribute(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    function InstrText(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode): TLandrixXmlUtf8;
    procedure DoProcessingInstruction(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      R: TReceiver);
    procedure DoMessage(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode);
    procedure DoDocument(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure DoApplyTemplates(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      R: TReceiver);
    procedure DoUseAttributeSets(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      R: TReceiver);
    procedure DoNamespace(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      R: TReceiver);
    procedure DoCallTemplate(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      R: TReceiver);
    function NumberMatches(Instr: TXsltInstr; Count: Boolean; Node, Model: Integer): Boolean;
    procedure DoNumber(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; R: TReceiver);
    procedure Located(Instr: TXsltInstr; E: ELandrixXmlXPathError);
    function Supplied(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode): TSuppliedArray;
    function Tunnelled(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode): TSuppliedArray;
    procedure ApplyTemplates(Instr: TXsltInstr; const Nodes: TLandrixXmlXPathSequence; Mode: TXsltMode;
      const Params: TSuppliedArray; R: TReceiver);
    procedure CheckStack(Local: Pointer; const Module: TLandrixXmlUtf8; Line, Column: Integer);
    procedure Invoke(T: TXsltTemplate; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      const Params: TSuppliedArray; R: TReceiver);
    procedure BindParams(T: TXsltTemplate; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      const Params: TSuppliedArray);
    procedure TypedBody(T: TXsltTemplate; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    function FindRule(Mode: TXsltMode; Node: Integer; After: TXsltRule; Lowest, Highest: Integer): TXsltRule;
    procedure DoNextMatch(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure DoResultDocument(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode);
    function CallFunction(T: TXsltTemplate; const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    procedure BuiltIn(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      const Params: TSuppliedArray; R: TReceiver);
    procedure BindGlobals;
  public
    constructor Create(Compiled: TXsltCompiled; Settings: TXsltRunSettings; Source: TLandrixXmlXPathTree);
    destructor Destroy; override;
    { a finished tree: owned by the run, added to the evaluator }
    function AddTree(Tree: TLandrixXmlXPathTree): Integer;
    procedure CopyNode(Node: Integer; R: TReceiver);
    procedure AddRawText(Node: Integer);
    function IsRawText(Node: Integer): Boolean;
    procedure Start(Target: TLandrixXmlXPathTree);
    property Evaluator: TLandrixXmlXPathEvaluator read FEvaluator;
  end;

function NoFocus: TLandrixXmlXPathFocus;
begin
  Result.Node := -1;
  Result.Item := LandrixXmlXPathEmpty;
  Result.Position := 0;
  Result.Size := 0;
end;

function NodeFocus(Node, Position, Size: Integer): TLandrixXmlXPathFocus;
begin
  Result.Node := Node;
  Result.Item := LandrixXmlXPathEmpty;
  Result.Position := Position;
  Result.Size := Size;
end;

function ItemFocus(const It: TLandrixXmlXPathItem; Position, Size: Integer): TLandrixXmlXPathFocus;
begin
  if It.Kind = xikNode then
    Result := NodeFocus(It.Node, Position, Size)
  else
  begin
    Result.Node := -1;
    Result.Item := LandrixXmlXPathEmpty;
    LandrixXmlXPathAppend(Result.Item, It);
    Result.Position := Position;
    Result.Size := Size;
  end;
end;

{ S itself if it has at most one item, else a sequence of its first item }
function FirstOf(const S: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
begin
  if S.Count <= 1 then
    Result := S
  else
  begin
    Result := LandrixXmlXPathEmpty;
    LandrixXmlXPathAppend(Result, S.Items[0]);
  end;
end;

{ S without white space around it }
function Trim8(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
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

{ the byte index of Sub in S (0 if none), without a conversion to string }
function Pos8(const Sub, S: TLandrixXmlUtf8): Integer;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) - Length(Sub) + 1 do
  begin
    J := 1;
    while (J <= Length(Sub)) and (S[I + J - 1] = Sub[J]) do
      Inc(J);
    if J > Length(Sub) then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

{ A comment's text as XSLT 2.0 (11.6) repairs it: a space after a "-"
  followed by "-" or at the end. }
function CommentText(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    Result := Result + Copy(S, I, 1);
    if (S[I] = '-') and ((I = Length(S)) or (S[I + 1] = '-')) then
      Result := Result + ' ';
  end;
end;

{ A processing instruction's text (11.7): "?>" becomes "? >", leading
  white space goes. }
function PIText(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and (S[I] in [#9, #10, #13, ' ']) do
    Inc(I);
  Result := '';
  while I <= Length(S) do
  begin
    Result := Result + Copy(S, I, 1);
    if (S[I] = '?') and (I < Length(S)) and (S[I + 1] = '>') then
      Result := Result + ' ';
    Inc(I);
  end;
end;

{ --- TXsltRunSettings -------------------------------------------------------- }

procedure TXsltRunSettings.AddParameter(const Name: TLandrixXmlUtf8; Kind: Integer; const Value: TLandrixXmlUtf8;
  Tree: TLandrixXmlXPathTree);
var
  N: Integer;
begin
  N := Integer(Length(ParamNames));
  SetLength(ParamNames, N + 1);
  SetLength(ParamKinds, N + 1);
  SetLength(ParamValues, N + 1);
  SetLength(ParamTrees, N + 1);
  ParamNames[N] := Name;
  ParamKinds[N] := Kind;
  ParamValues[N] := Value;
  ParamTrees[N] := Tree;
end;

{ --- receivers ------------------------------------------------------------------ }

constructor TReceiver.Create(ARun: TRun);
begin
  inherited Create;
  FRun := ARun;
end;

procedure TReceiver.Item(const It: TLandrixXmlXPathItem; Copy: Boolean);
begin
  if Copy and (It.Kind = xikNode) then
    CopyItem(It)
  else
    AddItem(It);
end;

{ disable-output-escaping where Saxon keeps it and this processor cannot
  (FOER0000, located by the instruction that runs) }
procedure RawUnsupported;
begin
  raise ELandrixXmlXPathError.CreateXPathAt(xecUnsupported, 'FOER0000', 'disable-output-escaping for text that ' +
    'is put into a temporary tree or a node built in a sequence is not supported', 0, 0);
end;

procedure TReceiver.RawCharacters(const S: TLandrixXmlUtf8);
begin
  Characters(S);
end;

procedure TReceiver.InheritedNamespaces(var Prefixes, Uris: TLandrixXmlUtf8Array);
begin
  Prefixes := nil;
  Uris := nil;
end;

procedure TReceiver.ForceNamespace(const Prefix, Uri: TLandrixXmlUtf8);
begin
  NamespaceNode(Prefix, Uri);
end;

{ the scope; a pending element is completed first (its namespace fixup:
  only called when content follows) }
procedure TTreeReceiver.InheritedNamespaces(var Prefixes, Uris: TLandrixXmlUtf8Array);

  procedure Add(const P, U: TLandrixXmlUtf8);
  var
    K, N: Integer;
  begin
    for K := 0 to Integer(Length(Prefixes)) - 1 do
      if Prefixes[K] = P then
      begin
        Uris[K] := U;
        Exit;
      end;
    N := Integer(Length(Prefixes));
    SetLength(Prefixes, N + 1);
    SetLength(Uris, N + 1);
    Prefixes[N] := P;
    Uris[N] := U;
  end;

var
  I: Integer;
begin
  Prefixes := nil;
  Uris := nil;
  Flush;
  for I := 0 to FScopeCount - 1 do
    Add(FScopePrefixes[I], FScopeUris[I]);
end;

procedure TTreeReceiver.ForceNamespace(const Prefix, Uri: TLandrixXmlUtf8);
var
  N: Integer;
begin
  NamespaceNode(Prefix, Uri);
  N := Integer(Length(FForced));
  SetLength(FForced, N + 1);
  FForced[N] := Prefix;
end;

function TTreeReceiver.IsForced(const Prefix: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to Integer(Length(FForced)) - 1 do
    if FForced[I] = Prefix then
      Exit;
  Result := False;
end;

procedure TSequenceReceiver.InheritedNamespaces(var Prefixes, Uris: TLandrixXmlUtf8Array);
begin
  if FInner <> nil then
    FInner.InheritedNamespaces(Prefixes, Uris)
  else
  begin
    Prefixes := nil;
    Uris := nil;
  end;
end;

procedure TSequenceReceiver.ForceNamespace(const Prefix, Uri: TLandrixXmlUtf8);
begin
  if FInner <> nil then
    FInner.ForceNamespace(Prefix, Uri)
  else
    NamespaceNode(Prefix, Uri);
end;

procedure TReceiver.CopyItem(const It: TLandrixXmlXPathItem);
begin
  AddItem(It);
end;

constructor TTreeReceiver.Create(ARun: TRun; Tree: TLandrixXmlXPathTree; Document: Boolean);
begin
  inherited Create(ARun);
  FTree := Tree;
  FDocument := Document;
  SetLength(FMarks, 16);
end;

function TTreeReceiver.InScope(const Prefix: TLandrixXmlUtf8; out Uri: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  if Prefix = 'xml' then
  begin
    Uri := LandrixXmlNamespaceXml;
    Result := True;
    Exit;
  end;
  for I := FScopeCount - 1 downto 0 do
    if FScopePrefixes[I] = Prefix then
    begin
      Uri := FScopeUris[I];
      Result := (Uri <> '') or (Prefix = '');
      Exit;
    end;
  Uri := '';
  Result := Prefix = '';
end;

{ the binding of Prefix for the pending element: its declarations, then
  the scope }
function TTreeReceiver.Bound(const Prefix: TLandrixXmlUtf8; out Uri: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  for I := 0 to Integer(Length(FNsPrefixes)) - 1 do
    if FNsPrefixes[I] = Prefix then
    begin
      Uri := FNsUris[I];
      Result := True;
      Exit;
    end;
  Result := InScope(Prefix, Uri);
end;

procedure TTreeReceiver.Declare(const Prefix, Uri: TLandrixXmlUtf8);
var
  I: Integer;
begin
  for I := 0 to Integer(Length(FNsPrefixes)) - 1 do
    if FNsPrefixes[I] = Prefix then
    begin
      FNsUris[I] := Uri;
      Exit;
    end;
  I := Integer(Length(FNsPrefixes));
  SetLength(FNsPrefixes, I + 1);
  SetLength(FNsUris, I + 1);
  FNsPrefixes[I] := Prefix;
  FNsUris[I] := Uri;
end;

{ whether attribute Index may keep Prefix for Uri: no declaration of the
  element, the element's name or an attribute before it binds the prefix
  to another URI }
function TTreeReceiver.AttrPrefixFree(const Prefix, Uri: TLandrixXmlUtf8; Index: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (Prefix = 'xml') or (Prefix = 'xmlns') then
    Exit;
  for I := 0 to Integer(Length(FNsPrefixes)) - 1 do
    if (FNsPrefixes[I] = Prefix) and (FNsUris[I] <> Uri) then
      Exit;
  if (Prefix = FPrefix) and (FUri <> Uri) then
    Exit;
  for I := 0 to Index - 1 do
    if (FAttrUris[I] <> '') and (FAttrPrefixes[I] = Prefix) and (FAttrUris[I] <> Uri) then
      Exit;
  Result := True;
end;

{ Whether the pending element cannot bind Prefix to Uri: xml, its own
  declarations, the prefix of its name or of one of its attributes give
  the prefix another URI (an ancestor's binding can be redeclared, as
  Saxon does). }
function TTreeReceiver.Taken(const Prefix, Uri: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := True;
  if Prefix = 'xml' then
    Exit;
  for I := 0 to Integer(Length(FNsPrefixes)) - 1 do
    if (FNsPrefixes[I] = Prefix) and (FNsUris[I] <> Uri) then
      Exit;
  if (Prefix = FPrefix) and (FUri <> Uri) then
    Exit;
  for I := 0 to FAttrCount - 1 do
    if (FAttrUris[I] <> '') and (FAttrPrefixes[I] = Prefix) and (FAttrUris[I] <> Uri) then
      Exit;
  Result := False;
end;

{ a prefix for Uri the pending element can declare, as Saxon makes one:
  the prefix, "_" and a number from First on (for an attribute without a
  prefix "ns0" itself first) }
function TTreeReceiver.FreePrefix(const Prefix, Uri: TLandrixXmlUtf8; First: Integer): TLandrixXmlUtf8;
var
  N: Integer;
  Base: TLandrixXmlUtf8;
begin
  Base := Prefix;
  { an element without a prefix: _0 on (Saxon) }
  if (Base = '') and (First > 0) then
  begin
    Base := 'ns0';
    Result := Base;
    if not Taken(Result, Uri) then
      Exit;
  end;
  N := First;
  repeat
    Result := Base + '_' + LandrixXmlStringToUtf8(IntToStr(N));
    Inc(N);
  until not Taken(Result, Uri);
end;

procedure TTreeReceiver.Flush;
var
  I, J, N: Integer;
  Uri, P: TLandrixXmlUtf8;
  Prefixes, Uris: TLandrixXmlUtf8Array;
begin
  if not FPending then
    Exit;
  FPending := False;
  { the element's name }
  if FUri = '' then
  begin
    FPrefix := '';
    Bound('', Uri);
    if Uri <> '' then
    begin
      { the undeclaration first, as Saxon writes it (a declaration of the
        default namespace the element was given is replaced) }
      N := 0;
      while (N < Length(FNsPrefixes)) and (FNsPrefixes[N] <> '') do
        Inc(N);
      if N = Length(FNsPrefixes) then
      begin
        SetLength(FNsPrefixes, N + 1);
        SetLength(FNsUris, N + 1);
      end;
      for I := N downto 1 do
      begin
        FNsPrefixes[I] := FNsPrefixes[I - 1];
        FNsUris[I] := FNsUris[I - 1];
      end;
      FNsPrefixes[0] := '';
      FNsUris[0] := '';
    end;
  end
  else if FUri = LandrixXmlNamespaceXml then
    FPrefix := 'xml'
  else if not Bound(FPrefix, Uri) or (Uri <> FUri) then
  begin
    { a prefix the declarations already give another URI: another prefix }
    if FPrefix = 'xml' then
    begin
      FPrefix := 'xml_0';
      if Bound(FPrefix, Uri) and (Uri <> FUri) then
        FPrefix := FreePrefix('xml', FUri, 1);
    end
    else
      for I := 0 to Integer(Length(FNsPrefixes)) - 1 do
        if (FNsPrefixes[I] = FPrefix) and (FNsUris[I] <> FUri) then
        begin
          { an element from _0 on, an attribute from _1 (Saxon) }
          FPrefix := FreePrefix(FPrefix, FUri, 0);
          Break;
        end;
    Declare(FPrefix, FUri);
  end;
  { attributes in a namespace need a prefix bound to it }
  for I := 0 to FAttrCount - 1 do
    if FAttrUris[I] <> '' then
    begin
      if (FAttrPrefixes[I] <> '') and Bound(FAttrPrefixes[I], Uri) and (Uri = FAttrUris[I]) then
        Continue;
      { the attribute's own prefix where nothing binds it otherwise (Saxon),
        else one bound to its URI, else a new one }
      if (FAttrPrefixes[I] <> '') and AttrPrefixFree(FAttrPrefixes[I], FAttrUris[I], I) then
      begin
        Declare(FAttrPrefixes[I], FAttrUris[I]);
        Continue;
      end;
      P := '';
      for J := 0 to Integer(Length(FNsPrefixes)) - 1 do
        if (FNsPrefixes[J] <> '') and (FNsUris[J] = FAttrUris[I]) then
          P := FNsPrefixes[J];
      if P = '' then
        for J := FScopeCount - 1 downto 0 do
          if (FScopePrefixes[J] <> '') and (FScopeUris[J] = FAttrUris[I]) and Bound(FScopePrefixes[J], Uri) and
            (Uri = FAttrUris[I]) then
          begin
            P := FScopePrefixes[J];
            Break;
          end;
      if P = '' then
      begin
        P := FAttrPrefixes[I];
        if (P = '') or Taken(P, FAttrUris[I]) then
          { from the position of the attribute on (Saxon) }
          P := FreePrefix(P, FAttrUris[I], I + 1);
        Declare(P, FAttrUris[I]);
      end;
      FAttrPrefixes[I] := P;
    end
    else
      FAttrPrefixes[I] := '';
  { declarations the scope already has are not repeated }
  Prefixes := nil;
  Uris := nil;
  for I := 0 to Integer(Length(FNsPrefixes)) - 1 do
  begin
    if InScope(FNsPrefixes[I], Uri) and (Uri = FNsUris[I]) and not IsForced(FNsPrefixes[I]) then
      Continue;
    if (FNsPrefixes[I] = '') and (FNsUris[I] = '') and not InScope('', Uri) then
      Continue;
    if (FNsPrefixes[I] = '') and (FNsUris[I] = '') and (Uri = '') then
      Continue;
    N := Integer(Length(Prefixes));
    SetLength(Prefixes, N + 1);
    SetLength(Uris, N + 1);
    Prefixes[N] := FNsPrefixes[I];
    Uris[N] := FNsUris[I];
  end;
  FTree.BuildStartElement(FUri, FPrefix, FLocal);
  for I := 0 to Integer(Length(Prefixes)) - 1 do
    FTree.BuildNamespace(Prefixes[I], Uris[I]);
  for I := 0 to FAttrCount - 1 do
    FTree.BuildAttribute(FAttrUris[I], FAttrPrefixes[I], FAttrLocals[I], FAttrValues[I]);
  { the scope of the element's content }
  if FDepth >= Length(FMarks) then
    SetLength(FMarks, 2 * FDepth + 16);
  FMarks[FDepth - 1] := FScopeCount;
  for I := 0 to Integer(Length(Prefixes)) - 1 do
  begin
    if FScopeCount = Length(FScopePrefixes) then
    begin
      SetLength(FScopePrefixes, 2 * FScopeCount + 8);
      SetLength(FScopeUris, 2 * FScopeCount + 8);
    end;
    FScopePrefixes[FScopeCount] := Prefixes[I];
    FScopeUris[FScopeCount] := Uris[I];
    Inc(FScopeCount);
  end;
  FNsPrefixes := nil;
  FNsUris := nil;
  FForced := nil;
  FAttrCount := 0;
  FAttrHashed := 0;
end;

procedure TTreeReceiver.Content;
begin
  Flush;
  FLastAtomic := False;
  FWritten := True;
end;

procedure TTreeReceiver.StartElement(const Uri, Prefix, Local: TLandrixXmlUtf8);
begin
  Content;
  FPending := True;
  FUri := Uri;
  FPrefix := Prefix;
  FLocal := Local;
  FNsPrefixes := nil;
  FNsUris := nil;
  FAttrCount := 0;
  FAttrHashed := 0;
  Inc(FDepth);
end;

procedure TTreeReceiver.NamespaceNode(const Prefix, Uri: TLandrixXmlUtf8);
var
  Existing: TLandrixXmlUtf8;
  I: Integer;
begin
  if not FPending then
  begin
    if FDepth = 0 then
      raise ELandrixXmlXPathError.CreateXPath('XTDE0420', 'a namespace node without an element');
    raise ELandrixXmlXPathError.CreateXPath('XTDE0410', 'a namespace node after the content of an element');
  end;
  if Prefix = 'xml' then
    Exit;
  if (Prefix = '') and (Uri <> '') and (FUri = '') then
    raise ELandrixXmlXPathError.CreateXPath('XTDE0440', 'a default namespace for an element in no namespace');
  { the element's own declarations decide a clash (the element's name) }
  for I := 0 to Integer(Length(FNsPrefixes)) - 1 do
    if FNsPrefixes[I] = Prefix then
    begin
      Existing := FNsUris[I];
      if Existing <> Uri then
        raise ELandrixXmlXPathError.CreateXPath('XTDE0430', 'two namespace nodes with the prefix "' +
          LandrixXmlUtf8ToString(Prefix) + '"');
      Exit;
    end;
  Declare(Prefix, Uri);
end;

const
  { below this many attributes a linear duplicate check is cheaper }
  AttrHashFrom = 16;

function TTreeReceiver.AttrHash(const Uri, Local: TLandrixXmlUtf8): Cardinal;
begin
  { no namespace: nothing to cache, the cached URI stays }
  if Uri = '' then
  begin
    Result := LandrixXmlHashFinish(LandrixXmlHashBytes(PAnsiChar(Local), Length(Local),
      LandrixXmlHashSalt));
    Exit;
  end;
  if Pointer(Uri) <> Pointer(FHashedUri) then
  begin
    FHashedUri := Uri;
    FHashedUriHash := LandrixXmlHashBytes(PAnsiChar(Uri), Length(Uri), LandrixXmlHashSalt);
  end;
  Result := LandrixXmlHashFinish(LandrixXmlHashBytes(PAnsiChar(Local), Length(Local),
    FHashedUriHash));
end;

function TTreeReceiver.FindAttr(const Uri, Local: TLandrixXmlUtf8): Integer;
var
  Mask, Slot, I: Integer;
begin
  if FAttrHashed = 0 then
  begin
    for I := 0 to FAttrCount - 1 do
      if (FAttrUris[I] = Uri) and (FAttrLocals[I] = Local) then
      begin
        Result := I;
        Exit;
      end;
    Result := -1;
    Exit;
  end;
  Mask := Integer(Length(FAttrSlots)) - 1;
  Slot := Integer(AttrHash(Uri, Local) and Cardinal(Mask));
  while FAttrSlots[Slot] >= 0 do
  begin
    Result := FAttrSlots[Slot];
    if (FAttrLocals[Result] = Local) and (FAttrUris[Result] = Uri) then
      Exit;
    Slot := (Slot + 1) and Mask;
  end;
  Result := -1;
end;

{ enters the attributes not yet in the table, rebuilding it when it is
  half full }
procedure TTreeReceiver.IndexAttrs;
var
  Size, Mask, Slot, I, First: Integer;
begin
  if FAttrCount < AttrHashFrom then
    Exit;
  First := FAttrHashed;
  if (FAttrHashed = 0) or (2 * FAttrCount > Length(FAttrSlots)) then
  begin
    Size := 64;
    while Size < 4 * FAttrCount do
      Size := Size * 2;
    SetLength(FAttrSlots, Size);
    for I := 0 to Size - 1 do
      FAttrSlots[I] := -1;
    First := 0;
  end;
  Mask := Integer(Length(FAttrSlots)) - 1;
  for I := First to FAttrCount - 1 do
  begin
    Slot := Integer(AttrHash(FAttrUris[I], FAttrLocals[I]) and Cardinal(Mask));
    while FAttrSlots[Slot] >= 0 do
      Slot := (Slot + 1) and Mask;
    FAttrSlots[Slot] := I;
  end;
  FAttrHashed := FAttrCount;
end;

procedure TTreeReceiver.Attribute(const Uri, Prefix, Local, Value: TLandrixXmlUtf8);
var
  I: Integer;
begin
  if not FPending then
  begin
    if (FDepth = 0) and FAttributesAsText then
    begin
      Characters(Value);
      Exit;
    end;
    if FDepth = 0 then
      raise ELandrixXmlXPathError.CreateXPath('XTDE0420', 'an attribute without an element')
    else
      raise ELandrixXmlXPathError.CreateXPath('XTDE0410', 'an attribute after the content of an element');
  end;
  FLastAtomic := False;
  I := FindAttr(Uri, Local);
  if I >= 0 then
  begin
    FAttrPrefixes[I] := Prefix;
    FAttrValues[I] := Value;
    Exit;
  end;
  if FAttrCount = Length(FAttrUris) then
  begin
    SetLength(FAttrUris, 2 * FAttrCount + 8);
    SetLength(FAttrPrefixes, 2 * FAttrCount + 8);
    SetLength(FAttrLocals, 2 * FAttrCount + 8);
    SetLength(FAttrValues, 2 * FAttrCount + 8);
  end;
  FAttrUris[FAttrCount] := Uri;
  FAttrPrefixes[FAttrCount] := Prefix;
  FAttrLocals[FAttrCount] := Local;
  FAttrValues[FAttrCount] := Value;
  Inc(FAttrCount);
  IndexAttrs;
end;

procedure TTreeReceiver.Characters(const S: TLandrixXmlUtf8);
begin
  { an empty text node still separates atomic values (and is written) }
  if S = '' then
  begin
    FLastAtomic := False;
    FWritten := True;
    Exit;
  end;
  Content;
  FTree.BuildText(S);
end;

{ the raw part is recorded with the text node it ends up in (adjacent
  text is merged) }
procedure TTreeReceiver.RawCharacters(const S: TLandrixXmlUtf8);
var
  N: Integer;
begin
  if FRawFails and (S <> '') then
    RawUnsupported;
  if (FRawProps = nil) or (S = '') then
  begin
    Characters(S);
    Exit;
  end;
  Content;
  N := FTree.Count;
  FTree.BuildText(S);
  if FTree.Count > N then
    FRawProps.AddRaw(N, 1, Length(S))
  else
    FRawProps.AddRaw(N - 1, FTree.ValueLength(N - 1) - Length(S) + 1, Length(S));
end;

procedure TTreeReceiver.Comment(const S: TLandrixXmlUtf8);
begin
  Content;
  FTree.BuildComment(S);
end;

procedure TTreeReceiver.ProcessingInstruction(const Target, S: TLandrixXmlUtf8);
begin
  Content;
  FTree.BuildProcessingInstruction(Target, S);
end;

procedure TTreeReceiver.EndElement;
begin
  Content;
  FTree.BuildEndElement;
  Dec(FDepth);
  FScopeCount := FMarks[FDepth];
end;

procedure TTreeReceiver.AddItem(const It: TLandrixXmlXPathItem);
var
  S: TLandrixXmlUtf8;
begin
  if It.Kind <> xikNode then
  begin
    S := FRun.Evaluator.ItemString(It);
    FWritten := True;
    if FLastAtomic then
      S := ' ' + S;
    if S <> '' then
    begin
      Flush;
      FTree.BuildText(S);
    end;
    FLastAtomic := True;
    Exit;
  end;
  if FRun.IsRawText(It.Node) and not FRawIgnored then
  begin
    { Saxon keeps it raw in a temporary tree too (implementation-defined) }
    if FRawProps = nil then
      RawUnsupported;
    RawCharacters(FRun.Evaluator.ItemString(It));
  end
  else
    FRun.CopyNode(It.Node, Self);
end;

{ xsl:copy-of: a copy is never raw (Saxon) }
procedure TTreeReceiver.CopyItem(const It: TLandrixXmlXPathItem);
begin
  FRun.CopyNode(It.Node, Self);
end;

procedure TTreeReceiver.Finish;
begin
  Flush;
  FTree.EndBuild;
end;

{ whether S starts with a URI scheme (RFC 3986: a letter, then letters,
  digits, "+", "-" or ".", then ":") }
function HasScheme(const S: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (S = '') or not (S[1] in ['A'..'Z', 'a'..'z']) then
    Exit;
  I := 2;
  while (I <= Length(S)) and (S[I] in ['A'..'Z', 'a'..'z', '0'..'9', '+', '-', '.']) do
    Inc(I);
  Result := (I <= Length(S)) and (S[I] = ':');
end;

{ the xml:base attribute of element N of T (False if it has none) }
function XmlBaseOf(T: TLandrixXmlXPathTree; N: Integer; out Value: TLandrixXmlUtf8): Boolean;
var
  A: Integer;
begin
  Result := True;
  for A := N + 1 to N + T.AttributeCount[N] do
    if (T.LocalNameUtf8(A) = 'base') and (T.NamespaceUriUtf8(A) = LandrixXmlNamespaceXml) then
    begin
      Value := T.ValueUtf8(A);
      Exit;
    end;
  Value := '';
  Result := False;
end;

constructor TSequenceReceiver.Create(ARun: TRun);
begin
  inherited Create(ARun);
  FItems := LandrixXmlXPathEmpty;
end;

destructor TSequenceReceiver.Destroy;
begin
  FInner.Free;
  FInnerTree.Free;
  inherited Destroy;
end;

{ a node at the top: a tree of its own }
procedure TSequenceReceiver.SetNextBase(const Uri: TLandrixXmlUtf8);
begin
  if FInner <> nil then
    Exit;
  FNextBase := Uri;
  FHasNextBase := True;
end;

procedure TSequenceReceiver.StartNode;
begin
  FTreeBase := BaseUri;
  if FHasNextBase then
    FTreeBase := FNextBase;
  FHasNextBase := False;
  FInnerTree := TLandrixXmlXPathTree.Create;
  FInnerTree.BeginBuild(False);
  FInner := TTreeReceiver.Create(FRun, FInnerTree, False);
end;

procedure TSequenceReceiver.EndNode;
var
  Base: Integer;
  T: TLandrixXmlXPathTree;
begin
  FInner.Finish;
  FInner.Free;
  FInner := nil;
  T := FInnerTree;
  FInnerTree := nil;
  { a parentless attribute, text, comment or processing instruction has
    no base URI }
  if (T.Count > 0) and (T.Kind[0] in [xnkElement, xnkDocument]) then
    T.BaseUri := FTreeBase;
  Base := FRun.AddTree(T);
  LandrixXmlXPathAppend(FItems, LandrixXmlXPathNodeItem(Base).Items[0]);
end;

procedure TSequenceReceiver.StartElement(const Uri, Prefix, Local: TLandrixXmlUtf8);
begin
  if FInner = nil then
    StartNode;
  FInner.StartElement(Uri, Prefix, Local);
end;

procedure TSequenceReceiver.NamespaceNode(const Prefix, Uri: TLandrixXmlUtf8);
begin
  if FInner = nil then
    raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT: a namespace node in a sequence is not supported');
  FInner.NamespaceNode(Prefix, Uri);
end;

procedure TSequenceReceiver.Attribute(const Uri, Prefix, Local, Value: TLandrixXmlUtf8);
begin
  if FInner <> nil then
  begin
    FInner.Attribute(Uri, Prefix, Local, Value);
    Exit;
  end;
  StartNode;
  FInnerTree.BuildAttribute(Uri, Prefix, Local, Value);
  EndNode;
end;

procedure TSequenceReceiver.Characters(const S: TLandrixXmlUtf8);
begin
  if FInner <> nil then
  begin
    FInner.Characters(S);
    Exit;
  end;
  StartNode;
  FInnerTree.BuildText(S);
  EndNode;
end;

{ a raw text node at the top of the sequence is remembered (inside a node
  being built the text is not raw) }
procedure TSequenceReceiver.RawCharacters(const S: TLandrixXmlUtf8);
begin
  { Saxon keeps it raw in a node built in a sequence (implementation-defined) }
  if (FInner <> nil) and (S <> '') then
    RawUnsupported;
  Characters(S);
  if (FInner = nil) and (S <> '') and (FItems.Count > 0) and (FItems.Items[FItems.Count - 1].Kind = xikNode) then
    FRun.AddRawText(FItems.Items[FItems.Count - 1].Node);
end;

procedure TSequenceReceiver.Comment(const S: TLandrixXmlUtf8);
begin
  if FInner <> nil then
  begin
    FInner.Comment(S);
    Exit;
  end;
  StartNode;
  FInnerTree.BuildComment(S);
  EndNode;
end;

procedure TSequenceReceiver.ProcessingInstruction(const Target, S: TLandrixXmlUtf8);
begin
  if FInner <> nil then
  begin
    FInner.ProcessingInstruction(Target, S);
    Exit;
  end;
  StartNode;
  FInnerTree.BuildProcessingInstruction(Target, S);
  EndNode;
end;

procedure TSequenceReceiver.EndElement;
begin
  FInner.EndElement;
  if FInner.Depth = 0 then
    EndNode;
end;

procedure TSequenceReceiver.AddItem(const It: TLandrixXmlXPathItem);
begin
  if FInner <> nil then
    FInner.AddItem(It)
  else
    LandrixXmlXPathAppend(FItems, It);
end;

procedure TSequenceReceiver.CopyItem(const It: TLandrixXmlXPathItem);
var
  U: TLandrixXmlUtf8;
  T: TLandrixXmlXPathTree;
  Builder: TTreeReceiver;
  B: Integer;
  Tree: TLandrixXmlXPathTree;
begin
  if FInner <> nil then
  begin
    FInner.CopyItem(It);
    Exit;
  end;
  Tree := FRun.Evaluator.TreeOfNode(It.Node, B);
  { an attribute, text, comment or processing instruction: a tree of its
    own through this receiver }
  if not (Tree.Kind[It.Node - B] in [xnkDocument, xnkElement]) then
  begin
    FRun.CopyNode(It.Node, Self);
    Exit;
  end;
  { a copy: a new tree (a document stays a document) }
  T := TLandrixXmlXPathTree.Create;
  try
    T.BeginBuild(Tree.Kind[It.Node - B] = xnkDocument);
    Builder := TTreeReceiver.Create(FRun, T, Tree.Kind[It.Node - B] = xnkDocument);
    try
      FRun.CopyNode(It.Node, Builder);
      Builder.Finish;
    finally
      Builder.Free;
    end;
    { the original's base URI; with a copied xml:base, that value resolved
      against the static base of the xsl:copy-of (the copied attribute
      applies once more, as in Saxon) }
    if (Tree.Kind[It.Node - B] = xnkElement) and XmlBaseOf(Tree, It.Node - B, U) then
      T.BaseUri := LandrixXmlXPathResolveUri(U, CopyBase)
    else if LandrixXmlXPathNodeBaseUri(Tree, It.Node - B, U) then
      T.BaseUri := U;
  except
    T.Free;
    raise;
  end;
  B := FRun.AddTree(T);
  LandrixXmlXPathAppend(FItems, LandrixXmlXPathNodeItem(B).Items[0]);
end;

{ --- the run ------------------------------------------------------------------------ }


type
  { the node numbers of one key value }
  TKeyNodes = class
  public
    Nodes: array of Integer;
    Count: Integer;
    procedure Add(Node: Integer);
  end;

  { the index of a key in one tree: key value (AtomKey) -> TKeyNodes }
  TKeyIndex = class
  public
    Key: TXsltKey;
    Root: Integer;
    { being built (a use expression that needs the same key: XTDE0640) }
    Building: Boolean;
    Map: TXsltStringList;
    constructor Create;
    destructor Destroy; override;
  end;

procedure TKeyNodes.Add(Node: Integer);
begin
  if (Count > 0) and (Nodes[Count - 1] = Node) then
    Exit;
  if Count = Length(Nodes) then
    SetLength(Nodes, 2 * Count + 4);
  Nodes[Count] := Node;
  Inc(Count);
end;

constructor TKeyIndex.Create;
begin
  inherited Create;
  Map := TXsltStringList.Create;
  Map.CaseSensitive := True;
  Map.Sorted := True;
end;

destructor TKeyIndex.Destroy;
var
  I: Integer;
begin
  for I := 0 to Integer(Map.Count) - 1 do
    Map.Objects[I].Free;
  Map.Free;
  inherited Destroy;
end;

{ S with each ' doubled (in an XPath string literal) }
function ReplaceQuotes(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    Result := Result + Copy(S, I, 1);
    if S[I] = '''' then
      Result := Result + '''';
  end;
end;

constructor TRun.Create(Compiled: TXsltCompiled; Settings: TXsltRunSettings; Source: TLandrixXmlXPathTree);
var
  I: Integer;
  Lit: TLandrixXmlUtf8;
  Def: TLandrixXmlXPathFunctionDef;
begin
  inherited Create;
  FC := Compiled;
  FSettings := Settings;
  FTrees := TObjectList.Create;
  FResults := TObjectList.Create;
  { URIs are compared as written (ordinal, case matters) }
  FResultUris := TXsltStringList.Create;
  FResultUris.CaseSensitive := True;
  FDefs := TObjectList.Create;
  FFunctions := TList.Create;
  FParamExprs := TObjectList.Create;
  FDocUris := TXsltStringList.Create;
  FDocUris.CaseSensitive := True;
  FResolver := Settings.Resolver;
  if FResolver = nil then
  begin
    FResolver := TLandrixXmlXsltResolver.Create;
    FOwnResolver := True;
  end;
  FSource := Source;
  FGivenSource := Source;
  if FSource = nil then
  begin
    FEmpty := TLandrixXmlXPathTree.Create;
    FSource := FEmpty;
  end
  else if FC.HasStrip then
  begin
    FStripped := StrippedCopy(Source);
    FSource := FStripped;
  end;
  FEvaluator := TLandrixXmlXPathEvaluator.Create(FSource);
  FTrue := TLandrixXmlXPathExpression.Create('true()', nil);
  FNumberExpr := TLandrixXmlXPathExpression.Create('number(.)', nil);
  FDoubleExpr := TLandrixXmlXPathExpression.Create('xs:double(.)', nil);
  FTimes100Expr := TLandrixXmlXPathExpression.Create('. * 100', nil);
  FTimes1000Expr := TLandrixXmlXPathExpression.Create('. * 1000', nil);
  FKeyNormExpr := TLandrixXmlXPathExpression.Create(
    'if (. instance of xs:QName) then concat(''{'', namespace-uri-from-QName(.), ''}'', local-name-from-QName(.)) ' +
    'else if (. instance of xs:dateTime and exists(timezone-from-dateTime(.))) ' +
    'then string(adjust-dateTime-to-timezone(., xs:dayTimeDuration(''PT0S''))) ' +
    'else if (. instance of xs:time and exists(timezone-from-time(.))) ' +
    'then string(adjust-time-to-timezone(., xs:dayTimeDuration(''PT0S''))) else string(.)', nil);
  FKeyIndexes := TObjectList.Create;
  FRoundExpr := TLandrixXmlXPathExpression.Create(
    'if (number(.) != number(.) or round(number(.)) lt 0) then -1 ' +
    'else if (round(number(.)) gt 2147483647) then -2 else xs:integer(round(number(.)))', nil);
  FDateTypes[xdkDateTime] := LandrixXmlXPathParseSequenceType('xs:dateTime?', nil);
  FDateTypes[xdkDate] := LandrixXmlXPathParseSequenceType('xs:date?', nil);
  FDateTypes[xdkTime] := LandrixXmlXPathParseSequenceType('xs:time?', nil);
  FStringType := LandrixXmlXPathParseSequenceType('xs:string', nil);
  FIntegerType := LandrixXmlXPathParseSequenceType('xs:integer', nil);
  FOptionalStringType := LandrixXmlXPathParseSequenceType('xs:string?', nil);
  FBaseExprs := TObjectList.Create;
  for I := 0 to Integer(Length(FC.ModuleUris)) - 1 do
  begin
    Lit := '''' + ReplaceQuotes(FC.ModuleUris[I]) + '''';
    if FC.ModuleUris[I] = '' then
    begin
      FBaseExprs.Add(TLandrixXmlXPathExpression.Create('()', nil));
      FBaseExprs.Add(TLandrixXmlXPathExpression.Create('resolve-uri(.)', nil));
    end
    else
    begin
      FBaseExprs.Add(TLandrixXmlXPathExpression.Create('xs:anyURI(' + Lit + ')', nil));
      FBaseExprs.Add(TLandrixXmlXPathExpression.Create('resolve-uri(., ' + Lit + ')', nil));
    end;
  end;
  FFalse := TLandrixXmlXPathExpression.Create('false()', nil);
  { one definition per function of the static contexts, in their order }
  for I := 0 to Integer(Length(FC.FunctionNames)) - 1 do
  begin
    Def := TLandrixXmlXPathFunctionDef.Create;
    Def.Name := LandrixXmlUtf8ToString(XsltClarkOf(FC.FunctionUris[I], FC.FunctionNames[I]));
    Def.Host := Host;
    Def.Tag := I;
    FDefs.Add(Def);
    FFunctions.Add(Def);
  end;
  FEvaluator.Functions := FFunctions;
  FEvaluator.MaxDepth := Settings.MaxDepth;
  { the stack is measured here, from the start of the run (CheckStack in
    Host and at template and function calls) }
  FEvaluator.MaxStackBytes := 0;
  FEvaluator.ImplicitTimeZone := Settings.ImplicitTimeZone;
  if Settings.HasClock then
    FEvaluator.CurrentDateTime := Settings.Clock;
end;

destructor TRun.Destroy;
begin
  if FOwnResolver then
    FResolver.Free;
  FDocUris.Free;
  FEvaluator.Free;
  FTrue.Free;
  FRoundExpr.Free;
  FNumberExpr.Free;
  FDoubleExpr.Free;
  FKeyNormExpr.Free;
  FTimes100Expr.Free;
  FTimes1000Expr.Free;
  FKeyIndexes.Free;
  FBaseExprs.Free;
  FFalse.Free;
  FParamExprs.Free;
  FFunctions.Free;
  FDefs.Free;
  FTrees.Free;
  FPrincipal.Free;
  FPrincipalProps.Free;
  FResultUris.Free;
  FResults.Free;
  FEmpty.Free;
  FStripped.Free;
  inherited Destroy;
end;

{ The resolver's answer; a resource it finds but cannot open (a locked
  file, no read permission) is not available either }
function TRun.OpenResource(Kind: TLandrixXmlXsltResourceKind; const Base, Href: TLandrixXmlUtf8;
  out Uri: TLandrixXmlUtf8; out Content: TStream): Boolean;
begin
  Uri := '';
  Content := nil;
  try
    Result := FResolver.Resolve(Kind, Base, Href, Uri, Content);
  except
    on EStreamError do
    begin
      Content := nil;
      Result := False;
    end;
    on EInOutError do
    begin
      Content := nil;
      Result := False;
    end;
  end;
end;

{ The node number of the document Href (relative to Base), read once per
  run; -1 if it is not available (Available) or else FODC0002. }
function TRun.LoadDocument(const Href, Base: TLandrixXmlUtf8; Available: Boolean): Integer;
var
  Uri, Key: TLandrixXmlUtf8;
  Content: TStream;
  Tree, Stripped: TLandrixXmlXPathTree;
  Reader: TLandrixXmlReader;
  I: Integer;
begin
  Result := -1;
  Content := nil;
  { a document read before is not resolved again }
  Key := LandrixXmlXPathResolveUri(Href, Base);
  I := FDocUris.IndexOf(LandrixXmlUtf8ToKey(Key));
  if I >= 0 then
    Result := FDocNodes[I]
  else if OpenResource(xrkDocument, Base, Href, Uri, Content) then
  begin
    I := FDocUris.IndexOf(LandrixXmlUtf8ToKey(Uri));
    if I >= 0 then
    begin
      Content.Free;
      Result := FDocNodes[I];
    end
    else
    begin
      Tree := TLandrixXmlXPathTree.Create;
      Reader := TLandrixXmlReader.Create;
      try
        try
          Reader.LoadFromStream(Content);
          Tree.LoadFromReader(Reader);
          Tree.BaseUri := Uri;
          if FC.HasStrip then
          begin
            Stripped := StrippedCopy(Tree);
            Tree.Free;
            Tree := Stripped;
          end;
          Result := AddTree(Tree);
          Tree := nil;
        except
          on E: ELandrixXmlError do
            if not Available then
              raise ELandrixXmlXPathError.CreateXPath('FODC0002', 'the document ' + LandrixXmlUtf8ToString(Uri) +
                ' is not well-formed: ' + E.Message);
        end;
      finally
        Reader.Free;
        Tree.Free;
        Content.Free;
      end;
      FDocUris.Add(LandrixXmlUtf8ToKey(Uri));
      SetLength(FDocNodes, FDocUris.Count);
      FDocNodes[Integer(FDocUris.Count) - 1] := Result;
    end;
    if Key <> Uri then
    begin
      FDocUris.Add(LandrixXmlUtf8ToKey(Key));
      SetLength(FDocNodes, FDocUris.Count);
      FDocNodes[Integer(FDocUris.Count) - 1] := Result;
    end;
  end;
  if (Result < 0) and not Available then
    raise ELandrixXmlXPathError.CreateXPath('FODC0002', 'the document ' + LandrixXmlUtf8ToString(Href) +
      ' is not available');
end;

{ Sorts the first Count numbers of A in ascending order (a bottom-up merge
  sort: key() and document() get many numbers in any order) and drops
  the repeated ones; the new count }
function SortUniqueIntegers(var A: array of Integer; Count: Integer): Integer;
var
  Tmp: array of Integer;
  Width, Lo, Mid, Hi, I, J, K: Integer;
  Sorted: Boolean;
begin
  Tmp := nil;
  Sorted := True;
  for I := 1 to Count - 1 do
    if A[I] < A[I - 1] then
    begin
      Sorted := False;
      Break;
    end;
  if not Sorted then
  begin
    SetLength(Tmp, Count);
    Width := 1;
    while Width < Count do
    begin
      Lo := 0;
      while Lo < Count do
      begin
        if Width >= Count - Lo then
          Mid := Count
        else
          Mid := Lo + Width;
        if Width >= Count - Mid then
          Hi := Count
        else
          Hi := Mid + Width;
        I := Lo;
        J := Mid;
        K := Lo;
        while (I < Mid) and (J < Hi) do
        begin
          if A[J] < A[I] then
          begin
            Tmp[K] := A[J];
            Inc(J);
          end
          else
          begin
            Tmp[K] := A[I];
            Inc(I);
          end;
          Inc(K);
        end;
        while I < Mid do
        begin
          Tmp[K] := A[I];
          Inc(I);
          Inc(K);
        end;
        while J < Hi do
        begin
          Tmp[K] := A[J];
          Inc(J);
          Inc(K);
        end;
        Lo := Hi;
      end;
      for I := 0 to Count - 1 do
        A[I] := Tmp[I];
      if Width >= Count - Width then
        Break;
      Width := 2 * Width;
    end;
  end;
  J := 0;
  for I := 0 to Count - 1 do
    if (J = 0) or (A[I] <> A[J - 1]) then
    begin
      A[J] := A[I];
      Inc(J);
    end;
  Result := J;
end;

{ doc(), doc-available(), document() of a module: relative URIs against
  the module's base URI (document(): a node's own base URI) }
function TRun.DocFunction(Kind, Module: Integer; const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  Base, Href, NodeBase: TLandrixXmlUtf8;
  I, N, B, Count: Integer;
  T: TLandrixXmlXPathTree;
  Found: array of Integer;
begin
  Result := LandrixXmlXPathEmpty;
  if Kind = XfnStaticBaseUri then
  begin
    Result := FEvaluator.EvaluateInFocus(TLandrixXmlXPathExpression(FBaseExprs[2 * Module]), NoFocus);
    Exit;
  end;
  if High(Args) < 0 then
    Exit;
  if Kind = XfnResolveUri then
  begin
    if Args[0].Count > 1 then
      raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'resolve-uri(): one URI was expected');
    if Args[0].Count > 0 then
      Result := FEvaluator.EvaluateInFocus(TLandrixXmlXPathExpression(FBaseExprs[2 * Module + 1]),
        ItemFocus(Args[0].Items[0], 1, 1));
    Exit;
  end;
  Base := FC.ModuleUris[Module];
  if Kind >= XfnUnparsedText1 then
  begin
    { the arguments one by one: with an open array FPC 3.2.2 -Cr hints
      that it is assigned but never used }
    if (Kind = XfnUnparsedText2) or (Kind = XfnUnparsedTextAvailable2) then
      Result := UnparsedText(Kind, Base, Args[0], Args[1])
    else
      Result := UnparsedText(Kind, Base, Args[0], Args[0]);
    Exit;
  end;
  if (Kind = XfnDocument) or (Kind = XfnDocument2) then
  begin
    { document(uris, node): the base URI of node for every relative URI }
    if Kind = XfnDocument2 then
    begin
      if (Args[1].Count <> 1) or (Args[1].Items[0].Kind <> xikNode) then
        raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'document(): the second argument must be one node');
      T := FEvaluator.TreeOfNode(Args[1].Items[0].Node, B);
      if not LandrixXmlXPathNodeBaseUri(T, Args[1].Items[0].Node - B, Base) then
        Base := '';
    end;
    Found := nil;
    Count := 0;
    for I := 0 to Args[0].Count - 1 do
    begin
      if (Args[0].Items[I].Kind = xikNode) and (Kind = XfnDocument) then
      begin
        { relative to the base URI of the node (its xml:base included) }
        T := FEvaluator.TreeOfNode(Args[0].Items[I].Node, B);
        Href := T.StringValueUtf8(Args[0].Items[I].Node - B);
        { a node without one (a temporary tree): the module's }
        if not LandrixXmlXPathNodeBaseUri(T, Args[0].Items[I].Node - B, NodeBase) or (NodeBase = '') then
          NodeBase := Base;
        N := LoadDocument(Href, NodeBase, False);
      end
      else
      begin
        Href := FEvaluator.ItemString(Args[0].Items[I]);
        { document#2: a relative URI needs the base URI of the node
          (XTDE1162); document#1 leaves an empty base to the resolver }
        if (Kind = XfnDocument2) and (Base = '') and not HasScheme(Href) then
          raise ELandrixXmlXPathError.CreateXPath('XTDE1162', 'document(): no base URI to resolve "' +
            LandrixXmlUtf8ToString(Href) + '" against');
        N := LoadDocument(Href, Base, False);
      end;
      if Count = Length(Found) then
        SetLength(Found, 2 * Count + 8);
      Found[Count] := N;
      Inc(Count);
    end;
    { a union: document order (the order the documents were read in),
      each document once }
    Count := SortUniqueIntegers(Found, Count);
    for I := 0 to Count - 1 do
      LandrixXmlXPathAppend(Result, LandrixXmlXPathNodeItem(Found[I]).Items[0]);
    Exit;
  end;
  if Args[0].Count = 0 then
  begin
    if Kind = XfnDocAvailable then
      Result := FEvaluator.EvaluateInFocus(FFalse, NoFocus);
    Exit;
  end;
  if Args[0].Count > 1 then
    raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'doc(): one URI was expected');
  Href := FEvaluator.ItemString(Args[0].Items[0]);
  if Kind = XfnDoc then
    Result := LandrixXmlXPathNodeItem(LoadDocument(Href, Base, False))
  else if LoadDocument(Href, Base, True) >= 0 then
    Result := FEvaluator.EvaluateInFocus(FTrue, NoFocus)
  else
    Result := FEvaluator.EvaluateInFocus(FFalse, NoFocus);
end;

function TRun.AddTree(Tree: TLandrixXmlXPathTree): Integer;
begin
  FTrees.Add(Tree);
  Result := FEvaluator.AddTree(Tree);
end;

procedure TRun.Fail(Instr: TXsltInstr; const Code, Msg: string);
begin
  if Instr <> nil then
    raise ELandrixXmlXsltError.CreateXslt(xecXslt, Code, Msg, Instr.Module, Instr.Line, Instr.Column)
  else
    raise ELandrixXmlXsltError.CreateXslt(xecXslt, Code, Msg, '', 0, 0);
end;

{ the value of a collation attribute value template (resolved against the
  static base URI): Code if it is not known as a collation }
procedure TRun.CheckCollation(Instr: TXsltInstr; const Uri: TLandrixXmlUtf8; const Code: string);
begin
  case XsltCollationKind(LandrixXmlXPathResolveUri(Uri, Instr.BaseUri)) of
    1:
      raise ELandrixXmlXsltError.CreateXslt(xecUnsupported, 'FOER0000',
        'a collation other than the codepoint collation is not supported', Instr.Module, Instr.Line, Instr.Column);
    2:
      Fail(Instr, Code, 'the collation "' + LandrixXmlUtf8ToString(Uri) + '" is not known');
  end;
end;

{ fn:string of the first item ('' for none), fn:number of it (NaN for
  none) }
function TRun.FirstStringSeq(const S: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
begin
  if S.Count = 0 then
    Result := LandrixXmlXPathStringItem('')
  else
    Result := LandrixXmlXPathStringItem(FEvaluator.ItemString(S.Items[0]));
end;

function TRun.FirstNumberSeq(const S: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  A: TLandrixXmlXPathSequence;
begin
  A := FEvaluator.DataOf(FirstOf(S));
  Result := LandrixXmlXPathEmpty;
  if A.Count = 0 then
    LandrixXmlXPathAppend(Result, FEvaluator.NumberOf(LandrixXmlXPathStringItem('NaN').Items[0]))
  else
    LandrixXmlXPathAppend(Result, FEvaluator.NumberOf(A.Items[0]));
end;

{ XSLT 2.0 section 3.8 for the functions of XSLT: the first item of a
  single-item argument (all but the values of key() and the URIs of
  document()), fn:string of a string argument and fn:number of a numeric
  one; user functions as XPath converts them (see CompatibleArgument).
  key() compares strings by its declarations, not by the caller. }
function TRun.HostCompatible(Evaluator: TLandrixXmlXPathEvaluator; Def: TLandrixXmlXPathFunctionDef;
  const Args: array of TLandrixXmlXPathSequence; const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
var
  A: array of TLandrixXmlXPathSequence;
  I: Integer;
  T: TXsltTemplate;
  P: TXsltInstr;
begin
  A := nil;
  SetLength(A, Length(Args));
  for I := 0 to Integer(High(Args)) do
    A[I] := Args[I];
  if Def.Tag >= FC.UserFunctionBase then
  begin
    T := TXsltTemplate(FC.UserFunctions[Def.Tag - FC.UserFunctionBase]);
    for I := 0 to Integer(T.Params.Count) - 1 do
    begin
      P := TXsltInstr(T.Params[I]);
      if (I <= High(A)) and P.HasAs then
        A[I] := FEvaluator.CompatibleArgument(A[I], P.AsType);
    end;
    Result := CallFunction(T, A);
    Exit;
  end;
  if Def.Tag >= XfnFixedCount then
  begin
    { doc, doc-available, unparsed-text and the others: string
      arguments, except the sequence of document() }
    case (Def.Tag - XfnFixedCount) mod XfnPerModule of
      XfnDocument, XfnDocument2:
        { the URIs stay a sequence; the base node: the first }
        for I := 1 to Integer(High(A)) do
          A[I] := FirstOf(A[I]);
    else
      for I := 0 to Integer(High(A)) do
        A[I] := FirstStringSeq(A[I]);
    end;
    Result := DocFunction((Def.Tag - XfnFixedCount) mod XfnPerModule, (Def.Tag - XfnFixedCount) div XfnPerModule,
      A);
    Exit;
  end;
  { every argument a single item, except the values of key() }
  for I := 0 to Integer(High(A)) do
    if not (((Def.Tag = XfnKey2) or (Def.Tag = XfnKey3)) and (I = 1)) then
      A[I] := FirstOf(A[I]);
  case Def.Tag of
    XfnKey2, XfnKey3:
      A[0] := FirstStringSeq(A[0]);
    XfnFormatNumber2, XfnFormatNumber3:
      begin
        A[0] := FirstNumberSeq(A[0]);
        for I := 1 to Integer(High(A)) do
          A[I] := FirstStringSeq(A[I]);
      end;
    XfnSystemProperty, XfnFunctionAvailable1, XfnElementAvailable, XfnFunctionAvailable2:
      A[0] := FirstStringSeq(A[0]);
    XfnFormatDateTime2, XfnFormatDateTime5, XfnFormatDate2, XfnFormatDate5, XfnFormatTime2, XfnFormatTime5:
      { the picture a string; language, calendar and place too, but they
        stay empty if they are }
      for I := 1 to Integer(High(A)) do
        if (I = 1) or (A[I].Count > 0) then
          A[I] := FirstStringSeq(A[I]);
  else
    { the others take no argument, or one XPath 1.0 does not have }
  end;
  FArgumentsConverted := True;
  Result := Host(Evaluator, Def, A, Focus);
end;

function TRun.Host(Evaluator: TLandrixXmlXPathEvaluator; Def: TLandrixXmlXPathFunctionDef;
  const Args: array of TLandrixXmlXPathSequence; const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
var
  G: TXsltGlobal;
  Slot, SavedNode: Integer;
  Arg, SavedCurrent: TLandrixXmlXPathSequence;
  SavedRegex: Boolean;
  SavedRule: TXsltRule;
  SavedTunnel: TSuppliedArray;
begin
  SavedTunnel := nil;
  Result := LandrixXmlXPathEmpty;
  { every host function, also what nests without a function or template
    (global variables, keys) }
  CheckStack(@Slot, '', 0, 0);
  { a caller in XPath 1.0 compatibility mode: HostCompatible converts the
    arguments and comes back here (FArgumentsConverted) }
  if not FArgumentsConverted and (Evaluator.CallerExpression <> nil) and
    Evaluator.CallerExpression.XPath10Compatible then
  begin
    Result := HostCompatible(Evaluator, Def, Args, Focus);
    Exit;
  end;
  FArgumentsConverted := False;
  if Def.Tag >= FC.UserFunctionBase then
  begin
    Result := CallFunction(TXsltTemplate(FC.UserFunctions[Def.Tag - FC.UserFunctionBase]), Args);
    Exit;
  end;
  if Def.Tag >= XfnFixedCount then
  begin
    Result := DocFunction((Def.Tag - XfnFixedCount) mod XfnPerModule, (Def.Tag - XfnFixedCount) div XfnPerModule,
      Args);
    Exit;
  end;
  case Def.Tag of
    XfnCurrentGroup:
      begin
        if not FGroupActive or (Evaluator.LazyDepth <> FGroupLazyDepth) then
          raise ELandrixXmlXPathError.CreateXPath('XTDE1061', 'there is no current group');
        Result := FGroup;
      end;
    XfnCurrentGroupingKey:
      begin
        if not FGroupActive or not FGroupHasKey or (Evaluator.LazyDepth <> FGroupLazyDepth) then
          raise ELandrixXmlXPathError.CreateXPath('XTDE1071', 'there is no current grouping key');
        Result := FGroupKey;
      end;
    XfnGenerateId0:
      begin
        if Focus.Node < 0 then
        begin
          if Focus.Item.Count = 0 then
            raise ELandrixXmlXPathError.CreateXPath('XPDY0002', 'generate-id(): there is no context item');
          raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'generate-id(): the context item is no node');
        end;
        Result := LandrixXmlXPathStringItem(GenerateId(Focus.Node));
      end;
    XfnGenerateId1:
      begin
        if (High(Args) < 0) or (Args[0].Count = 0) then
          Result := LandrixXmlXPathStringItem('')
        else if (Args[0].Count > 1) or (Args[0].Items[0].Kind <> xikNode) then
          raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'generate-id(): the argument must be one node')
        else
          Result := LandrixXmlXPathStringItem(GenerateId(Args[0].Items[0].Node));
      end;
    XfnKey2, XfnKey3:
      Result := KeyFunction(Args, Focus);
    { the arguments one by one (see UnparsedText) }
    XfnFunctionAvailable2:
      Result := Availability(Evaluator, Def.Tag, Args[0], Args[1]);
    XfnSystemProperty, XfnFunctionAvailable1, XfnElementAvailable:
      Result := Availability(Evaluator, Def.Tag, Args[0], Args[0]);
    XfnFormatNumber2, XfnFormatNumber3:
      Result := FormatNumber(Args);
    XfnRegexGroup:
      Result := RegexGroup(Args[0]);
    XfnFormatDateTime2, XfnFormatDateTime5:
      Result := FormatDate(xdkDateTime, Args);
    XfnFormatDate2, XfnFormatDate5:
      Result := FormatDate(xdkDate, Args);
    XfnFormatTime2, XfnFormatTime5:
      Result := FormatDate(xdkTime, Args);
    XfnCurrent:
      begin
        { the node the evaluator has (also that of a global variable
          being evaluated), else an atomic item of the instruction; an
          absent focus is that of a global without a source (an
          instruction's own focus is never absent when it has an item) }
        if Evaluator.CurrentNode >= 0 then
          Result := LandrixXmlXPathNodeItem(Evaluator.CurrentNode)
        else if (Focus.Node < 0) and (Focus.Item.Count = 0) then
          raise ELandrixXmlXPathError.CreateXPath('XPDY0002', 'current(): there is no current item')
        else if FCurrent.Count > 0 then
          Result := FCurrent
        else
          raise ELandrixXmlXPathError.CreateXPath('XPDY0002', 'current(): there is no current item');
      end;
    XfnGlobal:
      begin
        { the value of a global variable with a sequence constructor, in a
          frame of its own (its local variables) }
        Arg := LandrixXmlXPathEmpty;
        if High(Args) >= 0 then
          Arg := Args[0];
        Slot := StrToInt(LandrixXmlUtf8ToString(Evaluator.ItemString(Arg.Items[0])));
        G := TXsltGlobal(FC.Globals[Slot]);
        SavedNode := FEvaluator.CurrentNode;
        SavedCurrent := FCurrent;
        { nor the captured substrings of the instruction that needs it }
        SavedRegex := FRegexActive;
        FRegexActive := False;
        SavedRule := FRule;
        FRule := nil;
        SavedTunnel := FTunnel;
        FTunnel := nil;
        FEvaluator.PushFrame(G.FrameSize);
        try
          Result := VariableValue(nil, G.BaseUri, nil, G.Body, G.HasAs, G.AsType, G.Name, Focus, FC.FindMode(''));
        finally
          FEvaluator.PopFrame;
          FEvaluator.CurrentNode := SavedNode;
          FCurrent := SavedCurrent;
          FRegexActive := SavedRegex;
          FRule := SavedRule;
          FTunnel := SavedTunnel;
        end;
      end;
  end;
end;

{ format-dateTime(), format-date(), format-time(): the value converted as
  a function argument, the picture, language and calendar as strings }
function TRun.FormatDate(Kind: TXPathDateKind; const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
const
  Names: array[TXPathDateKind] of string = ('format-date', 'format-time', 'format-dateTime');
var
  V: TLandrixXmlXPathSequence;
  Picture, Language, Calendar: TLandrixXmlUtf8;

  { argument I as xs:string (One) or xs:string? }
  function Str(I: Integer; One: Boolean): TLandrixXmlUtf8;
  var
    S: TLandrixXmlXPathSequence;
  begin
    Result := '';
    if I > High(Args) then
      Exit;
    if One then
      S := FEvaluator.ConvertSequence(Args[I], FStringType, Names[Kind] + '()')
    else
      S := FEvaluator.ConvertSequence(Args[I], FOptionalStringType, Names[Kind] + '()');
    if S.Count > 0 then
      Result := FEvaluator.ItemString(S.Items[0]);
  end;

begin
  Result := LandrixXmlXPathEmpty;
  if High(Args) < 1 then
    Exit;
  V := FEvaluator.ConvertSequence(Args[0], FDateTypes[Kind], Names[Kind] + '()');
  Picture := Str(1, True);
  Language := Str(2, False);
  Calendar := Str(3, False);
  Str(4, False);
  if V.Count = 0 then
    Exit;
  Result := LandrixXmlXPathStringItem(XPathFormatDateTime(FEvaluator.ItemString(V.Items[0]), Kind, Picture,
    Language, Calendar, (High(Args) >= 2) and (Args[2].Count > 0), (High(Args) >= 3) and (Args[3].Count > 0)));
end;

{ XPath errors get the instruction's position }
function TRun.Eval(Instr: TXsltInstr; Expr: TLandrixXmlXPathExpression;
  const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
var
  Saved: TLandrixXmlXPathSequence;
begin
  Saved := FCurrent;
  FCurrent := Focus.Item;
  FEvaluator.CurrentNode := Focus.Node;
  try
    try
      Result := FEvaluator.EvaluateInFocus(Expr, Focus);
    finally
      FCurrent := Saved;
    end;
  except
    on E: ELandrixXmlXsltError do
      raise;
    on E: ELandrixXmlXPathError do
      if Instr <> nil then
        Located(Instr, E)
      else
        raise;
  end;
end;

{ Simple content (XSLT 2.0 5.7.2): zero-length text nodes dropped,
  adjacent text nodes merged, the rest joined with the separator. }
function TRun.SimpleContent(const S: TLandrixXmlXPathSequence; const Separator: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I, B: Integer;
  T: TLandrixXmlXPathTree;
  Text: TLandrixXmlUtf8;
  First, PrevText, IsText: Boolean;
begin
  Result := '';
  First := True;
  PrevText := False;
  for I := 0 to Integer(S.Count) - 1 do
  begin
    IsText := False;
    if S.Items[I].Kind = xikNode then
    begin
      T := FEvaluator.TreeOfNode(S.Items[I].Node, B);
      IsText := T.Kind[S.Items[I].Node - B] = xnkText;
    end;
    Text := FEvaluator.ItemString(S.Items[I]);
    if IsText and (Text = '') then
      Continue;
    if not First and not (IsText and PrevText) then
      Result := Result + Separator;
    Result := Result + Text;
    First := False;
    PrevText := IsText;
  end;
end;

function TRun.EvalString(Instr: TXsltInstr; Expr: TLandrixXmlXPathExpression;
  const Focus: TLandrixXmlXPathFocus; const Separator: TLandrixXmlUtf8): TLandrixXmlUtf8;
begin
  Result := SimpleContent(Eval(Instr, Expr, Focus), Separator);
end;

function TRun.FirstString(Instr: TXsltInstr; Expr: TLandrixXmlXPathExpression;
  const Focus: TLandrixXmlXPathFocus): TLandrixXmlUtf8;
var
  V, W: TLandrixXmlXPathSequence;
begin
  V := Eval(Instr, Expr, Focus);
  W := LandrixXmlXPathEmpty;
  if V.Count > 0 then
    LandrixXmlXPathAppend(W, V.Items[0]);
  Result := SimpleContent(W, '');
end;

function TRun.EvalAvt(Instr: TXsltInstr; Avt: TXsltAvt; const Focus: TLandrixXmlXPathFocus): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Integer(Length(Avt.Parts)) - 1 do
    if Avt.Exprs[I] = nil then
      Result := Result + Avt.Parts[I]
    else if Avt.Exprs[I].XPath10Compatible then
      { backwards compatible mode: the first item }
      Result := Result + FirstString(Instr, Avt.Exprs[I], Focus)
    else
      Result := Result + EvalString(Instr, Avt.Exprs[I], Focus, ' ');
end;

{ BodySequence in a temporary output state (sort keys) }
function TRun.TemporarySequence(Body: TObjectList; const Focus: TLandrixXmlXPathFocus;
  const Mode: TXsltMode): TLandrixXmlXPathSequence;
var
  Saved: Boolean;
begin
  Saved := FTemporary;
  FTemporary := True;
  try
    Result := BodySequence(Body, '', Focus, Mode);
  finally
    FTemporary := Saved;
  end;
end;

function TRun.BodySequence(Body: TObjectList; const BaseUri: TLandrixXmlUtf8; const Focus: TLandrixXmlXPathFocus;
  const Mode: TXsltMode): TLandrixXmlXPathSequence;
var
  R: TSequenceReceiver;
begin
  R := TSequenceReceiver.Create(Self);
  R.BaseUri := BaseUri;
  try
    Exec(Body, Focus, Mode, R);
    Result := R.Items;
  finally
    R.Free;
  end;
end;

{ a temporary tree: the document node of the result of Instr's select
  (if any) followed by its body (xsl:message) }
function TRun.ContentDocument(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus;
  const Mode: TXsltMode): TLandrixXmlXPathSequence;
var
  T: TLandrixXmlXPathTree;
  R: TTreeReceiver;
  S: TLandrixXmlXPathSequence;
  I: Integer;
  Saved: Boolean;
begin
  { a temporary output state }
  Saved := FTemporary;
  FTemporary := True;
  T := TLandrixXmlXPathTree.Create;
  try
    T.BeginBuild(True);
    R := TTreeReceiver.Create(Self, T, True);
    try
      { as Saxon: an attribute in a message is its value }
      R.FAttributesAsText := True;
      R.FRawIgnored := True;
      if Instr.Select <> nil then
      begin
        S := Eval(Instr, Instr.Select, Focus);
        for I := 0 to Integer(S.Count) - 1 do
          R.Item(S.Items[I], True);
      end;
      Exec(Instr.Body, Focus, Mode, R);
      R.Finish;
    finally
      R.Free;
    end;
  except
    FTemporary := Saved;
    T.Free;
    raise;
  end;
  FTemporary := Saved;
  Result := LandrixXmlXPathNodeItem(AddTree(T));
end;

{ a temporary tree: the document node of the body's result, with the
  static base URI of the instruction that makes it }
function TRun.BodyDocument(Body: TObjectList; const BaseUri: TLandrixXmlUtf8; const Focus: TLandrixXmlXPathFocus;
  const Mode: TXsltMode): TLandrixXmlXPathSequence;
var
  T: TLandrixXmlXPathTree;
  R: TTreeReceiver;
begin
  T := TLandrixXmlXPathTree.Create;
  try
    T.BeginBuild(True);
    R := TTreeReceiver.Create(Self, T, True);
    R.FRawFails := FDocumentRaw;
    FDocumentRaw := False;
    try
      Exec(Body, Focus, Mode, R);
      R.Finish;
    finally
      R.Free;
    end;
    { after the build (BeginBuild clears it) }
    T.BaseUri := BaseUri;
  except
    T.Free;
    raise;
  end;
  Result := LandrixXmlXPathNodeItem(AddTree(T));
end;

{ the simple content of the body's result }
function TRun.BodyString(Body: TObjectList; const Focus: TLandrixXmlXPathFocus;
  const Mode: TXsltMode; const Separator: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  Saved: Boolean;
begin
  { attributes, comments, processing instructions, value-of: a
    temporary output state }
  Saved := FTemporary;
  FTemporary := True;
  try
    Result := SimpleContent(BodySequence(Body, '', Focus, Mode), Separator);
  finally
    FTemporary := Saved;
  end;
end;

function TRun.VariableValue(Instr: TXsltInstr; const BaseUri: TLandrixXmlUtf8; Select: TLandrixXmlXPathExpression;
  Body: TObjectList;
  HasAs: Boolean; const AsType: TLandrixXmlXPathSequenceType; const Name: TLandrixXmlUtf8;
  const Focus: TLandrixXmlXPathFocus; const Mode: TXsltMode): TLandrixXmlXPathSequence;
var
  Saved: Boolean;
begin
  { variables and parameters: a temporary output state }
  Saved := FTemporary;
  FTemporary := True;
  try
    if Select <> nil then
      Result := Eval(Instr, Select, Focus)
    else if HasAs then
      Result := BodySequence(Body, BaseUri, Focus, Mode)
    else if Body.Count = 0 then
      Result := LandrixXmlXPathStringItem('')
    else
      Result := BodyDocument(Body, BaseUri, Focus, Mode);
  finally
    FTemporary := Saved;
  end;
  if HasAs then
    try
      Result := FEvaluator.ConvertSequence(Result, AsType, '$' + LandrixXmlUtf8ToString(Name));
    except
      on E: ELandrixXmlXPathError do
        if Instr <> nil then
          raise ELandrixXmlXsltError.CreateXslt(xecXslt, E.XPathCode,
            System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), Instr.Module, Instr.Line, Instr.Column)
        else
          raise;
    end;
end;

procedure TRun.Exec(Body: TObjectList; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  I: Integer;
begin
  for I := 0 to Integer(Body.Count) - 1 do
    ExecInstr(TXsltInstr(Body[I]), Focus, Mode, R);
end;

procedure TRun.LiteralElement(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  R: TReceiver);
var
  I: Integer;
  A: TXsltAttributeTemplate;
begin
  { an element at the top of a sequence: the instruction's static base }
  if R is TSequenceReceiver then
    TSequenceReceiver(R).SetNextBase(Instr.BaseUri);
  R.StartElement(Instr.NamespaceUri, Instr.Prefix, Instr.LocalName);
  for I := 0 to Integer(Length(Instr.NsPrefixes)) - 1 do
    R.NamespaceNode(Instr.NsPrefixes[I], Instr.NsUris[I]);
  { the attributes of the attribute sets first: the literal ones replace
    them }
  if Instr.UseSets <> nil then
    DoUseAttributeSets(Instr.UseSets, Focus, Mode, R);
  for I := 0 to Integer(Instr.Attributes.Count) - 1 do
  begin
    A := TXsltAttributeTemplate(Instr.Attributes[I]);
    R.Attribute(A.NamespaceUri, A.Prefix, A.LocalName, EvalAvt(Instr, A.Value, Focus));
  end;
  Exec(Instr.Body, Focus, Mode, R);
  R.EndElement;
end;

function IsNCName8(const S: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := (S <> '') and not (S[1] in ['0'..'9', '-', '.']);
  for I := 1 to Length(S) do
    if not ((S[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.']) or (Ord(S[I]) >= 128)) then
      Result := False;
end;

{ system-property(), function-available() and element-available() (see
  XsltSystemProperty and the functions beside it) }
function TRun.Availability(Evaluator: TLandrixXmlXPathEvaluator; Kind: Integer;
  const NameArg, ArityArg: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  Uri, Local: TLandrixXmlUtf8;
  Found: Boolean;
begin
  if Kind = XfnSystemProperty then
  begin
    XsltNameArgument(Evaluator, NameArg, 'XTDE1390', 'system-property()', '', Uri, Local);
    Result := LandrixXmlXPathStringItem(XsltSystemProperty(Uri, Local));
    Exit;
  end;
  if Kind = XfnElementAvailable then
  begin
    XsltNameArgument(Evaluator, NameArg, 'XTDE1440', 'element-available()', '#', Uri, Local);
    Found := (Uri = XsltNamespace) and XsltElementAvailable(Local);
  end
  else
  begin
    XsltNameArgument(Evaluator, NameArg, 'XTDE1400', 'function-available()', LandrixXmlXPathFunctionNamespace,
      Uri, Local);
    if Kind = XfnFunctionAvailable2 then
      Found := XsltFunctionAvailable(Evaluator, FC, Uri, Local, XsltArityArgument(Evaluator, ArityArg))
    else
      Found := XsltFunctionAvailable(Evaluator, FC, Uri, Local, -1);
  end;
  if Found then
    Result := Evaluator.EvaluateInFocus(FTrue, NoFocus)
  else
    Result := Evaluator.EvaluateInFocus(FFalse, NoFocus);
end;

procedure TRun.ComputedName(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Element: Boolean;
  out Uri, Prefix, Local: TLandrixXmlUtf8);
var
  Name: TLandrixXmlUtf8;
  I: Integer;
  Found: Boolean;
begin
  { a lexical QName: white space around it is allowed (XSLT 2.0 erratum E2) }
  Name := Trim8(EvalAvt(Instr, Instr.NameAvt, Focus));
  I := Pos8(':', Name);
  if I > 0 then
  begin
    Prefix := System.Copy(Name, 1, I - 1);
    Local := System.Copy(Name, I + 1, Length(Name) - I);
  end
  else
  begin
    Prefix := '';
    Local := Name;
  end;
  if not IsNCName8(Local) or ((I > 0) and not IsNCName8(Prefix)) then
  begin
    if Element then
      Fail(Instr, 'XTDE0820', 'not a valid element name: "' + LandrixXmlUtf8ToString(Name) + '"')
    else
      Fail(Instr, 'XTDE0850', 'not a valid attribute name: "' + LandrixXmlUtf8ToString(Name) + '"');
  end;
  if not Element and (Name = 'xmlns') then
    Fail(Instr, 'XTDE0855', 'an attribute cannot be named xmlns');
  if Instr.NamespaceAvt <> nil then
  begin
    Uri := EvalAvt(Instr, Instr.NamespaceAvt, Focus);
    if (Uri = '') then
      Prefix := ''
    else if Uri = LandrixXmlNamespaceXml then
      Prefix := 'xml';
    Exit;
  end;
  { the namespaces in scope at the instruction; the default namespace for
    an element only }
  Uri := '';
  if (Prefix = '') and not Element then
    Exit;
  Found := False;
  for I := 0 to Integer(Length(Instr.ScopePrefixes)) - 1 do
    if Instr.ScopePrefixes[I] = Prefix then
    begin
      Uri := Instr.ScopeUris[I];
      Found := True;
    end;
  if Prefix = 'xml' then
  begin
    Uri := LandrixXmlNamespaceXml;
    Found := True;
  end;
  if not Found and (Prefix <> '') then
  begin
    if Element then
      Fail(Instr, 'XTDE0830', 'the prefix "' + LandrixXmlUtf8ToString(Prefix) + '" is not declared')
    else
      Fail(Instr, 'XTDE0860', 'the prefix "' + LandrixXmlUtf8ToString(Prefix) + '" is not declared');
  end;
end;

{ A copy of Tree (a document or a tree without document node) without
  the white space text nodes xsl:strip-space removes: those whose parent
  element XsltStripsSpace names, unless the nearest xml:space attribute
  of the parent or an ancestor is "preserve". Positions in the source
  are not kept. }
function TRun.StrippedCopy(Tree: TLandrixXmlXPathTree): TLandrixXmlXPathTree;
var
  T: TLandrixXmlXPathTree;

  function IsWhite(const S: TLandrixXmlUtf8): Boolean;
  var
    I: Integer;
  begin
    Result := False;
    for I := 1 to Length(S) do
      if not (S[I] in [#9, #10, #13, ' ']) then
        Exit;
    Result := True;
  end;

  { Preserve: an xml:space="preserve" is in force at the parent }
  procedure Walk(I: Integer; Preserve: Boolean);
  var
    C, A, K: Integer;
    Prefixes, Uris: TLandrixXmlUtf8Array;
    Strip: Boolean;
  begin
    Prefixes := nil;
    Uris := nil;
    case Tree.Kind[I] of
      xnkDocument:
        begin
          C := Tree.FirstChild(I);
          while C >= 0 do
          begin
            Walk(C, False);
            C := Tree.NextSibling[C];
          end;
        end;
      xnkElement:
        begin
          T.BuildStartElement(Tree.NamespaceUriUtf8(I), Tree.PrefixUtf8(I), Tree.LocalNameUtf8(I));
          Tree.GetDeclarations(I, Prefixes, Uris);
          for K := 0 to Integer(Length(Prefixes)) - 1 do
            T.BuildNamespace(Prefixes[K], Uris[K]);
          for A := I + 1 to I + Tree.AttributeCount[I] do
          begin
            T.BuildAttribute(Tree.NamespaceUriUtf8(A), Tree.PrefixUtf8(A), Tree.LocalNameUtf8(A), Tree.ValueUtf8(A));
            { a value other than "preserve" counts as "default", as in
              Saxon }
            if (Tree.LocalNameUtf8(A) = 'space') and
              (Tree.NamespaceUriUtf8(A) = 'http://www.w3.org/XML/1998/namespace') then
              Preserve := Tree.ValueUtf8(A) = 'preserve';
          end;
          Strip := not Preserve and XsltStripsSpace(FC, Tree.NamespaceUriUtf8(I), Tree.LocalNameUtf8(I));
          C := Tree.FirstChild(I);
          while C >= 0 do
          begin
            if not (Strip and (Tree.Kind[C] = xnkText) and IsWhite(Tree.ValueUtf8(C))) then
              Walk(C, Preserve);
            C := Tree.NextSibling[C];
          end;
          T.BuildEndElement;
        end;
      xnkText:
        T.BuildText(Tree.ValueUtf8(I));
      xnkComment:
        T.BuildComment(Tree.ValueUtf8(I));
      xnkProcessingInstruction:
        T.BuildProcessingInstruction(Tree.LocalNameUtf8(I), Tree.ValueUtf8(I));
      xnkAttribute:
        { only an attribute at the top (those of an element are copied with
          it) }
        T.BuildAttribute(Tree.NamespaceUriUtf8(I), Tree.PrefixUtf8(I), Tree.LocalNameUtf8(I), Tree.ValueUtf8(I));
    end;
  end;

var
  I: Integer;
begin
  T := TLandrixXmlXPathTree.Create;
  try
    T.BeginBuild((Tree.Count > 0) and (Tree.Kind[0] = xnkDocument));
    if (Tree.Count > 0) and (Tree.Kind[0] = xnkDocument) then
      Walk(0, False)
    else
    begin
      I := 0;
      while (I >= 0) and (I < Tree.Count) do
      begin
        Walk(I, False);
        I := Tree.NextSibling[I];
      end;
    end;
    T.EndBuild;
    T.BaseUri := Tree.BaseUri;
  except
    T.Free;
    raise;
  end;
  Result := T;
end;

procedure TRun.AddRawText(Node: Integer);
begin
  if FRawTextCount = Length(FRawTexts) then
    SetLength(FRawTexts, 2 * FRawTextCount + 16);
  FRawTexts[FRawTextCount] := Node;
  Inc(FRawTextCount);
end;

{ the nodes are numbered in the order their trees are added: the list is
  sorted }
function TRun.IsRawText(Node: Integer): Boolean;
var
  Lo, Hi, Mid: Integer;
begin
  Result := False;
  Lo := 0;
  Hi := FRawTextCount - 1;
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if FRawTexts[Mid] = Node then
    begin
      Result := True;
      Exit;
    end;
    if FRawTexts[Mid] < Node then
      Lo := Mid + 1
    else
      Hi := Mid - 1;
  end;
end;

{ copy-namespaces="no" (FNoNamespaces) as Saxon does it: below the top of
  the copy an element has the namespaces its names need and those of the
  place the copy goes to (InsPrefixes, InsUris; its own names win), not
  those of its copied parent; one its names need that the copied parent
  does not have is declared again }
procedure TRun.CopyNode(Node: Integer; R: TReceiver);
var
  T: TLandrixXmlXPathTree;
  Base, Root: Integer;
  InsPrefixes, InsUris: TLandrixXmlUtf8Array;

  { the binding of Prefix the place of the copy gives }
  function Inserted(const Prefix: TLandrixXmlUtf8; out Uri: TLandrixXmlUtf8): Boolean;
  var
    K: Integer;
  begin
    for K := 0 to Integer(Length(InsPrefixes)) - 1 do
      if InsPrefixes[K] = Prefix then
      begin
        Uri := InsUris[K];
        Result := True;
        Exit;
      end;
    Uri := '';
    Result := False;
  end;

  { whether the names of element I (its own or an attribute's) use Prefix,
    with the URI }
  function NameUses(I: Integer; const Prefix: TLandrixXmlUtf8; out Uri: TLandrixXmlUtf8): Boolean;
  var
    A: Integer;
  begin
    Result := True;
    if (T.PrefixUtf8(I) = Prefix) and ((Prefix <> '') or (T.NamespaceUriUtf8(I) <> '')) then
    begin
      Uri := T.NamespaceUriUtf8(I);
      Exit;
    end;
    if Prefix <> '' then
      for A := I + 1 to I + T.AttributeCount[I] do
        if T.PrefixUtf8(A) = Prefix then
        begin
          Uri := T.NamespaceUriUtf8(A);
          Exit;
        end;
    Uri := '';
    Result := False;
  end;

  { whether the copy of the parent of I has the binding }
  function ParentHas(I: Integer; const Prefix, Uri: TLandrixXmlUtf8): Boolean;
  var
    P: Integer;
    U: TLandrixXmlUtf8;
  begin
    P := T.Parent[I];
    if (P >= 0) and (T.Kind[P] = xnkElement) and NameUses(P, Prefix, U) then
      Result := U = Uri
    else
      Result := Inserted(Prefix, U) and (U = Uri);
  end;

  { whether a copied ancestor of I has a name in no namespace (Saxon: its
    xmlns="" holds for the elements below, not the place's default) }
  function BelowNoNamespace(I: Integer): Boolean;
  var
    P: Integer;
  begin
    Result := True;
    P := I;
    while P <> Root do
    begin
      P := T.Parent[P];
      if (T.Kind[P] = xnkElement) and (T.PrefixUtf8(P) = '') and (T.NamespaceUriUtf8(P) = '') then
        Exit;
    end;
    Result := False;
  end;

  procedure NoNamespaces(I: Integer);
  var
    K, A: Integer;
    U: TLandrixXmlUtf8;
  begin
    { the place's namespaces the names do not override; the default one
      for a prefixed name only }
    for K := 0 to Integer(Length(InsPrefixes)) - 1 do
      if (InsPrefixes[K] <> '') and not NameUses(I, InsPrefixes[K], U) then
        R.NamespaceNode(InsPrefixes[K], InsUris[K]);
    if T.PrefixUtf8(I) <> '' then
    begin
      if BelowNoNamespace(I) or not Inserted('', U) then
        U := '';
      R.NamespaceNode('', U);
    end;
    { what the names need and the copied parent does not have }
    if (T.PrefixUtf8(I) <> '') and not ParentHas(I, T.PrefixUtf8(I), T.NamespaceUriUtf8(I)) then
      R.ForceNamespace(T.PrefixUtf8(I), T.NamespaceUriUtf8(I));
    for A := I + 1 to I + T.AttributeCount[I] do
      if (T.PrefixUtf8(A) <> '') and (T.PrefixUtf8(A) <> 'xml') and (T.PrefixUtf8(A) <> T.PrefixUtf8(I)) and
        not ParentHas(I, T.PrefixUtf8(A), T.NamespaceUriUtf8(A)) then
        R.ForceNamespace(T.PrefixUtf8(A), T.NamespaceUriUtf8(A));
  end;

  procedure Walk(I: Integer);
  var
    C, A, K: Integer;
    Prefixes, Uris: TLandrixXmlUtf8Array;
  begin
    Prefixes := nil;
    Uris := nil;
    case T.Kind[I] of
      xnkDocument:
        begin
          C := T.FirstChild(I);
          while C >= 0 do
          begin
            Walk(C);
            C := T.NextSibling[C];
          end;
        end;
      xnkElement:
        begin
          R.StartElement(T.NamespaceUriUtf8(I), T.PrefixUtf8(I), T.LocalNameUtf8(I));
          if not FNoNamespaces then
          begin
            T.InScopeNamespacesUtf8(I, Prefixes, Uris);
            for K := 0 to Integer(Length(Prefixes)) - 1 do
              if Prefixes[K] <> 'xml' then
                R.NamespaceNode(Prefixes[K], Uris[K]);
          end
          else if I <> Root then
            NoNamespaces(I);
          for A := I + 1 to I + T.AttributeCount[I] do
            R.Attribute(T.NamespaceUriUtf8(A), T.PrefixUtf8(A), T.LocalNameUtf8(A), T.ValueUtf8(A));
          C := T.FirstChild(I);
          while C >= 0 do
          begin
            Walk(C);
            C := T.NextSibling[C];
          end;
          R.EndElement;
        end;
      xnkAttribute:
        R.Attribute(T.NamespaceUriUtf8(I), T.PrefixUtf8(I), T.LocalNameUtf8(I), T.ValueUtf8(I));
      xnkText:
        R.Characters(T.ValueUtf8(I));
      xnkComment:
        R.Comment(T.ValueUtf8(I));
      xnkProcessingInstruction:
        R.ProcessingInstruction(T.LocalNameUtf8(I), T.ValueUtf8(I));
    end;
  end;

begin
  T := FEvaluator.TreeOfNode(Node, Base);
  Root := Node - Base;
  InsPrefixes := nil;
  InsUris := nil;
  { only where content follows: an element, a document with children }
  if FNoNamespaces and ((T.Kind[Root] = xnkElement) or (T.Kind[Root] = xnkDocument) and
    (T.FirstChild(Root) >= 0)) then
    R.InheritedNamespaces(InsPrefixes, InsUris);
  Walk(Root);
end;

{ xsl:copy: a shallow copy of the context item }
procedure TRun.CopyInstr(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  T: TLandrixXmlXPathTree;
  Base, I, K: Integer;
  Prefixes, Uris: TLandrixXmlUtf8Array;
  Uri: TLandrixXmlUtf8;
begin
  Prefixes := nil;
  Uris := nil;
  if Focus.Node < 0 then
  begin
    if Focus.Item.Count = 0 then
      Fail(Instr, 'XTTE0945', 'xsl:copy without a context item');
    R.Item(Focus.Item.Items[0], False);
    Exit;
  end;
  T := FEvaluator.TreeOfNode(Focus.Node, Base);
  I := Focus.Node - Base;
  case T.Kind[I] of
    xnkDocument:
      { a document node of its own (an attribute in it is XTDE0420; in a
        tree, its content stays apart from adjacent atomic values; raw
        text in it as in xsl:document) }
      begin
        FDocumentRaw := True;
        R.Item(BodyDocument(Instr.Body, T.BaseUri, Focus, Mode).Items[0], False);
      end;
    xnkElement:
      begin
        { a copy at the top of a sequence has the original's base URI (none
          if it has none) }
        if R is TSequenceReceiver then
        begin
          if not LandrixXmlXPathNodeBaseUri(T, I, Uri) then
            Uri := '';
          TSequenceReceiver(R).SetNextBase(Uri);
        end;
        R.StartElement(T.NamespaceUriUtf8(I), T.PrefixUtf8(I), T.LocalNameUtf8(I));
        { copy-namespaces="no": only the namespaces the names need }
        if not Instr.NoNamespaces then
        begin
          T.InScopeNamespacesUtf8(I, Prefixes, Uris);
          for K := 0 to Integer(Length(Prefixes)) - 1 do
            if Prefixes[K] <> 'xml' then
              R.NamespaceNode(Prefixes[K], Uris[K]);
        end;
        { use-attribute-sets applies to an element only }
        if Instr.UseSets <> nil then
          DoUseAttributeSets(Instr.UseSets, Focus, Mode, R);
        Exec(Instr.Body, Focus, Mode, R);
        R.EndElement;
      end;
  else
    CopyNode(Focus.Node, R);
  end;
end;

function TRun.Supplied(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode): TSuppliedArray;
var
  I, N: Integer;
  P: TXsltWithParam;
begin
  Result := nil;
  N := 0;
  for I := 0 to Integer(Instr.Params.Count) - 1 do
  begin
    P := TXsltWithParam(Instr.Params[I]);
    if P.Tunnel then
      Continue;
    SetLength(Result, N + 1);
    Result[N].Name := P.Name;
    Result[N].Value := VariableValue(Instr, P.BaseUri, P.Select, P.Body, P.HasAs, P.AsType, P.Name, Focus, Mode);
    Inc(N);
  end;
end;

{ the tunnel parameters for the templates Instr invokes: those received,
  with the tunnel xsl:with-param of Instr added (replacing one of the
  same name) }
function TRun.Tunnelled(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode): TSuppliedArray;
var
  I, J, N: Integer;
  P: TXsltWithParam;
begin
  Result := Copy(FTunnel, 0, Length(FTunnel));
  for I := 0 to Integer(Instr.Params.Count) - 1 do
  begin
    P := TXsltWithParam(Instr.Params[I]);
    if not P.Tunnel then
      Continue;
    N := Integer(Length(Result));
    for J := 0 to Integer(Length(Result)) - 1 do
      if Result[J].Name = P.Name then
        N := J;
    if N = Length(Result) then
      SetLength(Result, N + 1);
    Result[N].Name := P.Name;
    Result[N].Value := VariableValue(Instr, P.BaseUri, P.Select, P.Body, P.HasAs, P.AsType, P.Name, Focus, Mode);
  end;
end;

{ The first rule of Mode that matches Node, in the order rules are
  tried; only those after After (if not nil) and with a precedence from
  Lowest to Highest. }
function TRun.FindRule(Mode: TXsltMode; Node: Integer; After: TXsltRule; Lowest, Highest: Integer): TXsltRule;
var
  T: TLandrixXmlXPathTree;
  Base, I, A, B: Integer;
  Key: string;
  Named: TList;
  Cand: TXsltRule;
  UseNamed, Passed: Boolean;

  function Better(X, Y: TXsltRule): Boolean;
  begin
    { X is tried before Y }
    if X.Precedence <> Y.Precedence then
      Result := X.Precedence > Y.Precedence
    else if X.Priority <> Y.Priority then
      Result := X.Priority > Y.Priority
    else
      Result := X.Order > Y.Order;
  end;

begin
  Result := nil;
  T := FEvaluator.TreeOfNode(Node, Base);
  I := Node - Base;
  Named := nil;
  Key := '';
  if T.Kind[I] = xnkElement then
    Key := 'e' + LandrixXmlUtf8ToString(XsltClarkOf(T.NamespaceUriUtf8(I), T.LocalNameUtf8(I)))
  else if T.Kind[I] = xnkAttribute then
    Key := 'a' + LandrixXmlUtf8ToString(XsltClarkOf(T.NamespaceUriUtf8(I), T.LocalNameUtf8(I)));
  if (Key <> '') and Mode.Named.Find(Key, A) then
    Named := TList(Mode.Named.Objects[A]);
  { both lists in the order they are tried: merged }
  A := 0;
  B := 0;
  Passed := After = nil;
  FEvaluator.CurrentNode := Node;
  FCurrent := LandrixXmlXPathEmpty;
  while True do
  begin
    UseNamed := (Named <> nil) and (A < Named.Count) and
      ((B >= Mode.Others.Count) or Better(TXsltRule(Named[A]), TXsltRule(Mode.Others[B])));
    if not UseNamed and (B >= Mode.Others.Count) then
      Exit;
    if UseNamed then
    begin
      Cand := TXsltRule(Named[A]);
      Inc(A);
    end
    else
    begin
      Cand := TXsltRule(Mode.Others[B]);
      Inc(B);
    end;
    { the merged order is the same on every call: the rules after After
      are those that follow it here }
    if not Passed then
    begin
      Passed := Cand = After;
      Continue;
    end;
    if (Cand.Precedence < Lowest) or (Cand.Precedence > Highest) then
      Continue;
    if (After <> nil) and After.Explicit and (Cand.Template = After.Template) then
      Continue;
    if PatternMatches(Cand.Pattern, Node, Cand.Relative) then
    begin
      Result := Cand;
      Exit;
    end;
  end;
end;

{ the parameters of T in the new frame: supplied (converted) or their
  defaults }
procedure TRun.BindParams(T: TXsltTemplate; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  const Params: TSuppliedArray);
var
  I, J: Integer;
  P: TXsltInstr;
  Found: Boolean;
  V: TLandrixXmlXPathSequence;
  Given: TSuppliedArray;
begin
  Given := nil;
  for I := 0 to Integer(T.Params.Count) - 1 do
  begin
    P := TXsltInstr(T.Params[I]);
    Found := False;
    if P.Tunnel then
      Given := FTunnel
    else
      Given := Params;
    for J := 0 to Integer(Length(Given)) - 1 do
      if Given[J].Name = P.VarName then
      begin
        V := Given[J].Value;
        if P.HasAs then
          try
            V := FEvaluator.ConvertSequence(V, P.AsType, '$' + LandrixXmlUtf8ToString(P.VarName));
          except
            on E: ELandrixXmlXPathError do
              raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTTE0590',
                System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), P.Module, P.Line, P.Column);
          end;
        FEvaluator.BindValue(P.Slot, V);
        Found := True;
      end;
    if Found then
      Continue;
    if P.Required then
      raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTDE0700', 'the required parameter ' +
        LandrixXmlUtf8ToString(P.VarName) + ' is not supplied', P.Module, P.Line, P.Column);
    FEvaluator.BindValue(P.Slot, VariableValue(P, P.BaseUri, P.Select, P.Body, P.HasAs, P.AsType, P.VarName, Focus, Mode));
  end;
end;

{ the body of a template with "as": its result converted }
procedure TRun.TypedBody(T: TXsltTemplate; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  I: Integer;
  V: TLandrixXmlXPathSequence;
  S: TSequenceReceiver;
begin
  S := TSequenceReceiver.Create(Self);
  try
    Exec(T.Body, Focus, Mode, S);
    try
      V := FEvaluator.ConvertSequence(S.Items, T.AsType, 'template ' + LandrixXmlUtf8ToString(T.Name));
    except
      on E: ELandrixXmlXPathError do
        raise ELandrixXmlXsltError.CreateXslt(xecXslt, E.XPathCode,
          System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), T.Module, T.Line, T.Column);
    end;
  finally
    S.Free;
  end;
  for I := 0 to Integer(V.Count) - 1 do
    R.Item(V.Items[I], False);
end;

{ A stylesheet function: its arguments converted to the parameter types
  (XPTY0004, as Saxon reports it), its body run without focus in a frame of its own, the
  result converted to its type (XTTE0780). }
function TRun.CallFunction(T: TXsltTemplate; const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  I, SavedNode: Integer;
  P: TXsltInstr;
  V, SavedCurrent: TLandrixXmlXPathSequence;
  S: TSequenceReceiver;
  SavedGroupActive, SavedRegexActive, SavedTemporary: Boolean;
  SavedRule: TXsltRule;
  SavedTunnel: TSuppliedArray;
begin
  if FTemplateDepth >= FSettings.MaxTemplateDepth then
    raise ELandrixXmlXsltError.CreateXslt(xecLimit, 'FOER0000', 'templates and functions nested deeper than ' +
      IntToStr(FSettings.MaxTemplateDepth), T.Module, T.Line, T.Column);
  CheckStack(@I, T.Module, T.Line, T.Column);
  Inc(FTemplateDepth);
  { the caller's current() is still needed after the call; there is no
    current group inside a function }
  SavedNode := FEvaluator.CurrentNode;
  SavedCurrent := FCurrent;
  SavedGroupActive := FGroupActive;
  FGroupActive := False;
  { nor captured substrings of xsl:analyze-string }
  SavedRegexActive := FRegexActive;
  FRegexActive := False;
  { nor a current template rule; a temporary output state }
  SavedRule := FRule;
  FRule := nil;
  SavedTemporary := FTemporary;
  FTemporary := True;
  SavedTunnel := FTunnel;
  FTunnel := nil;
  FEvaluator.PushFrame(T.FrameSize);
  try
    for I := 0 to Integer(T.Params.Count) - 1 do
    begin
      P := TXsltInstr(T.Params[I]);
      V := LandrixXmlXPathEmpty;
      if I <= High(Args) then
        V := Args[I];
      if P.HasAs then
        try
          V := FEvaluator.ConvertSequence(V, P.AsType, '$' + LandrixXmlUtf8ToString(P.VarName));
        except
          on E: ELandrixXmlXPathError do
            raise ELandrixXmlXsltError.CreateXslt(xecXslt, E.XPathCode,
              System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), P.Module, P.Line, P.Column);
        end;
      FEvaluator.BindValue(P.Slot, V);
    end;
    S := TSequenceReceiver.Create(Self);
    try
      Exec(T.Body, NoFocus, FC.FindMode(''), S);
      Result := S.Items;
    finally
      S.Free;
    end;
    if T.HasAs then
      try
        Result := FEvaluator.ConvertSequence(Result, T.AsType, 'function ' + LandrixXmlUtf8ToString(T.Name));
      except
        on E: ELandrixXmlXPathError do
          raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTTE0780',
            System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), T.Module, T.Line, T.Column);
      end;
  finally
    FEvaluator.PopFrame;
    FEvaluator.CurrentNode := SavedNode;
    FCurrent := SavedCurrent;
    FGroupActive := SavedGroupActive;
    FRegexActive := SavedRegexActive;
    FRule := SavedRule;
    FTemporary := SavedTemporary;
    FTunnel := SavedTunnel;
    Dec(FTemplateDepth);
  end;
end;

{ Before a template or function call (Local: a variable of the caller's
  frame): the stack used since the start of the run against
  MaxStackBytes; a distance below zero or beyond 1 GB means another stack
  and is not checked. }
procedure TRun.CheckStack(Local: Pointer; const Module: TLandrixXmlUtf8; Line, Column: Integer);
var
  Used: Integer;
begin
  if FSettings.MaxStackBytes <= 0 then
    Exit;
  Used := Integer(PAnsiChar(FStackBase) - PAnsiChar(Local));
  if (Used > FSettings.MaxStackBytes) and (Used < 1073741824) then
    raise ELandrixXmlXsltError.CreateXslt(xecLimit, 'FOER0000', 'templates and functions nested ' +
      IntToStr(FTemplateDepth) + ' deep use more than ' + IntToStr(FSettings.MaxStackBytes) + ' bytes of stack',
      Module, Line, Column);
end;

procedure TRun.Invoke(T: TXsltTemplate; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  const Params: TSuppliedArray; R: TReceiver);
begin
  if FTemplateDepth >= FSettings.MaxTemplateDepth then
    raise ELandrixXmlXsltError.CreateXslt(xecLimit, 'FOER0000', 'templates nested deeper than ' +
      IntToStr(FSettings.MaxTemplateDepth), T.Module, T.Line, T.Column);
  CheckStack(@T, T.Module, T.Line, T.Column);
  Inc(FTemplateDepth);
  FEvaluator.PushFrame(T.FrameSize);
  try
    BindParams(T, Focus, Mode, Params);
    if T.HasAs then
      TypedBody(T, Focus, Mode, R)
    else
      Exec(T.Body, Focus, Mode, R);
  finally
    FEvaluator.PopFrame;
    Dec(FTemplateDepth);
  end;
end;

{ the built-in template rules }
procedure TRun.BuiltIn(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  const Params: TSuppliedArray; R: TReceiver);
var
  T: TLandrixXmlXPathTree;
  Base, C: Integer;
  Children: TLandrixXmlXPathSequence;
begin
  if Focus.Node < 0 then
  begin
    R.Item(Focus.Item.Items[0], False);
    Exit;
  end;
  T := FEvaluator.TreeOfNode(Focus.Node, Base);
  case T.Kind[Focus.Node - Base] of
    xnkDocument, xnkElement:
      begin
        Children := LandrixXmlXPathEmpty;
        C := T.FirstChild(Focus.Node - Base);
        while C >= 0 do
        begin
          LandrixXmlXPathAppend(Children, LandrixXmlXPathNodeItem(C + Base).Items[0]);
          C := T.NextSibling[C];
        end;
        { counted as a template (the depth of a tree is not limited) }
        if FTemplateDepth >= FSettings.MaxTemplateDepth then
        begin
          if Instr = nil then
            raise ELandrixXmlXsltError.CreateXslt(xecLimit, 'FOER0000', 'templates nested deeper than ' +
              IntToStr(FSettings.MaxTemplateDepth), '', 0, 0);
          raise ELandrixXmlXsltError.CreateXslt(xecLimit, 'FOER0000', 'templates nested deeper than ' +
            IntToStr(FSettings.MaxTemplateDepth), Instr.Module, Instr.Line, Instr.Column);
        end;
        if Instr = nil then
          CheckStack(@Base, '', 0, 0)
        else
          CheckStack(@Base, Instr.Module, Instr.Line, Instr.Column);
        Inc(FTemplateDepth);
        try
          ApplyTemplates(Instr, Children, Mode, Params, R);
        finally
          Dec(FTemplateDepth);
        end;
      end;
    xnkText, xnkAttribute:
      R.Characters(T.ValueUtf8(Focus.Node - Base));
  else
    { comments and processing instructions: nothing }
  end;
end;

procedure TRun.ApplyTemplates(Instr: TXsltInstr; const Nodes: TLandrixXmlXPathSequence; Mode: TXsltMode;
  const Params: TSuppliedArray; R: TReceiver);
var
  I: Integer;
  Rule, SavedRule: TXsltRule;
  F: TLandrixXmlXPathFocus;
begin
  Rule := nil;
  SavedRule := FRule;
  try
    for I := 0 to Integer(Nodes.Count) - 1 do
    begin
      F := ItemFocus(Nodes.Items[I], I + 1, Nodes.Count);
      if Nodes.Items[I].Kind <> xikNode then
      begin
        { XSLT 3.0 lets atomic values through the built-in rule; 2.0 errs }
        Fail(Instr, 'XTTE0520', 'xsl:apply-templates selects an atomic value');
      end;
      try
        Rule := FindRule(Mode, Nodes.Items[I].Node, nil, 0, MaxInt);
      except
        on E: ELandrixXmlXsltError do
          raise;
        on E: ELandrixXmlXPathError do
          Located(Instr, E);
      end;
      FRule := Rule;
      if Rule = nil then
        BuiltIn(Instr, F, Mode, Params, R)
      else
        Invoke(Rule.Template, F, Mode, Params, R);
    end;
  finally
    FRule := SavedRule;
  end;
end;

function XsltHasUriScheme(const S: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (S = '') or not (S[1] in ['A'..'Z', 'a'..'z']) then
    Exit;
  { from 2: a single letter is a drive (C:\out), not a scheme }
  for I := 2 to Length(S) do
    if S[I] = ':' then
    begin
      Result := I > 2;
      Exit;
    end
    else if not (S[I] in ['A'..'Z', 'a'..'z', '0'..'9', '+', '-', '.']) then
      Exit;
end;

{ xsl:result-document: the body becomes a tree of its own, with the
  output properties of the format (else xsl:output) and the attributes;
  without href (or one that resolves to the base output URI) it is the
  principal result }
procedure TRun.DoResultDocument(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode);
var
  Href, Uri, Name, V, Names, Bad: TLandrixXmlUtf8;
  Props: TXsltOutputProperties;
  T: TLandrixXmlXPathTree;
  R: TTreeReceiver;
  I, P, Index: Integer;
  Principal: Boolean;
begin
  if FTemporary then
    Fail(Instr, 'XTDE1480', 'xsl:result-document in a temporary output state');
  Href := '';
  if Instr.HrefAvt <> nil then
    Href := Trim8(EvalAvt(Instr, Instr.HrefAvt, Focus));
  Props := nil;
  T := nil;
  try
    if Instr.FormatAvt <> nil then
    begin
      { a QName with the namespaces of the instruction (no default) or an
        EQName }
      Name := Trim8(EvalAvt(Instr, Instr.FormatAvt, Focus));
      if not FC.NamedOutputs.Find(LandrixXmlUtf8ToString(XsltFormatClark(Name, Instr.ScopePrefixes,
        Instr.ScopeUris)), P) then
        Fail(Instr, 'XTDE1460', 'no xsl:output named ' + LandrixXmlUtf8ToString(Name));
      Props := TXsltOutputProperties(FC.NamedOutputs.Objects[P]).Clone;
    end
    else
      Props := FC.Output.Clone;
    { use-character-maps: added to the maps of the output definition }
    if Instr.MapProps <> nil then
      Props.AddMappings(TXsltOutputProperties(Instr.MapProps));
    { cdata-section-elements: added to the output definition's }
    if Instr.CDataAvt <> nil then
    begin
      V := EvalAvt(Instr, Instr.CDataAvt, Focus);
      if not XsltCDataNames(V, Instr.ScopePrefixes, Instr.ScopeUris, Names, Bad) then
        Fail(Instr, 'XTDE0030', 'not a QName (or its prefix is not declared) in cdata-section-elements: "' +
          LandrixXmlUtf8ToString(Bad) + '"');
      Props.AddCDataElements(Names);
    end;
    for I := 0 to Integer(Length(Instr.OutputNames)) - 1 do
    begin
      V := Trim8(EvalAvt(Instr, Instr.OutputAvts[I], Focus));
      case XsltOutputPropertyStatus(Instr.OutputNames[I], V) of
        xosUnsupported:
          raise ELandrixXmlXsltError.CreateXslt(xecUnsupported, 'FOER0000', 'xsl:result-document ' +
            LandrixXmlUtf8ToString(Instr.OutputNames[I]) + '="' + LandrixXmlUtf8ToString(V) + '" is not supported',
            Instr.Module, Instr.Line, Instr.Column);
        xosInvalid, xosUnknown:
          Fail(Instr, 'XTDE0030', 'xsl:result-document ' + LandrixXmlUtf8ToString(Instr.OutputNames[I]) + '="' +
            LandrixXmlUtf8ToString(V) + '" is not a valid value');
      else
        { supported }
      end;
      Props.SetValue(Instr.OutputNames[I], V);
    end;
    { the URI: href resolved against the base output URI }
    Principal := Href = '';
    if Principal then
      Uri := FSettings.BaseOutputUri
    else
    begin
      if (FSettings.BaseOutputUri = '') and not XsltHasUriScheme(Href) then
        Fail(Instr, 'FOER0000', 'the relative href "' + LandrixXmlUtf8ToString(Href) +
          '" needs a base output URI');
      Uri := LandrixXmlXPathResolveUri(Href, FSettings.BaseOutputUri);
      Principal := Uri = FSettings.BaseOutputUri;
    end;
    if Principal and ((FImplicit.Count > 1) or FImplicitReceiver.FPending or FImplicitReceiver.FWritten) then
      Fail(Instr, 'XTDE1490', 'the principal result has been written already');
    if FResultUris.IndexOf(LandrixXmlUtf8ToKey(Uri)) >= 0 then
      Fail(Instr, 'XTDE1490', 'a second result document with the URI ' + LandrixXmlUtf8ToString(Uri));
    FResultUris.Add(LandrixXmlUtf8ToKey(Uri));
    { in the order the instructions start (a nested one comes after) }
    Index := Integer(FResults.Count);
    T := TLandrixXmlXPathTree.Create;
    T.BeginBuild(True);
    R := TTreeReceiver.Create(Self, T, True);
    try
      R.FRawProps := Props;
      Exec(Instr.Body, Focus, Mode, R);
      R.Finish;
    finally
      R.Free;
    end;
    T.BaseUri := Uri;
    if Principal then
    begin
      FPrincipal := T;
      FPrincipalProps := Props;
    end
    else
      FResults.Insert(Index, TLandrixXmlXsltResultDocument.Create(Uri, T, Props));
  except
    T.Free;
    Props.Free;
    raise;
  end;
end;

{ xsl:next-match: the next rule after the current one that matches the
  context node; xsl:apply-imports: the first matching rule of the
  modules imported into the stylesheet level of the current one; both
  in the current mode, else the built-in rule }
procedure TRun.DoNextMatch(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  Params, Tunnel, SavedTunnel: TSuppliedArray;
  Rule, SavedRule: TXsltRule;
begin
  { the context item of a current template rule is the node it matched
    (xsl:for-each and xsl:analyze-string clear the rule) }
  if (FRule = nil) or (Focus.Node < 0) then
    Fail(Instr, 'XTDE0560', 'there is no current template rule');
  Params := Supplied(Instr, Focus, Mode);
  Tunnel := Tunnelled(Instr, Focus, Mode);
  Rule := nil;
  try
    if Instr.Kind = xskNextMatch then
      Rule := FindRule(Mode, Focus.Node, FRule, 0, MaxInt)
    else
      Rule := FindRule(Mode, Focus.Node, nil, FC.ImportLow[FRule.Precedence], FRule.Precedence - 1);
  except
    on E: ELandrixXmlXsltError do
      raise;
    on E: ELandrixXmlXPathError do
      Located(Instr, E);
  end;
  SavedRule := FRule;
  FRule := Rule;
  SavedTunnel := FTunnel;
  FTunnel := Tunnel;
  try
    if Rule = nil then
      BuiltIn(Instr, Focus, Mode, Params, R)
    else
      Invoke(Rule.Template, Focus, Mode, Params, R);
  finally
    FRule := SavedRule;
    FTunnel := SavedTunnel;
  end;
end;

{ raises E again with the instruction's position (if any) }
procedure TRun.Located(Instr: TXsltInstr; E: ELandrixXmlXPathError);
var
  Code: TLandrixXmlErrorCode;
begin
  { an unsupported feature met at run time stays unsupported }
  if E.Code = xecUnsupported then
    Code := xecUnsupported
  else
    Code := xecXslt;
  if Instr = nil then
    raise ELandrixXmlXsltError.CreateXslt(Code, E.XPathCode,
      System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), '', 0, 0);
  raise ELandrixXmlXsltError.CreateXslt(Code, E.XPathCode,
    System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), Instr.Module, Instr.Line, Instr.Column);
end;

procedure TRun.ExecInstr(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
begin
  try
    ExecCore(Instr, Focus, Mode, R);
  except
    on E: ELandrixXmlXsltError do
      raise;
    on E: ELandrixXmlXPathError do
      Located(Instr, E);
  end;
end;

{ One method per instruction: the dispatcher keeps no managed variables
  in its frame, so that deep template recursion needs little stack. }
procedure TRun.DoValueOf(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  Text, Sep: TLandrixXmlUtf8;
begin
  if Instr.Select <> nil then
    Sep := ' '
  else
    Sep := '';
  if Instr.Separator <> nil then
    Sep := EvalAvt(Instr, Instr.Separator, Focus);
  if (Instr.Select <> nil) and (Instr.Separator = nil) and Instr.Select.XPath10Compatible then
    { backwards compatible mode without a separator: the first item }
    Text := FirstString(Instr, Instr.Select, Focus)
  else if Instr.Select <> nil then
    Text := EvalString(Instr, Instr.Select, Focus, Sep)
  else
    Text := BodyString(Instr.Body, Focus, Mode, Sep);
  if Instr.NoEscape then
    R.RawCharacters(Text)
  else
    R.Characters(Text);
end;

{ xsl:text and text of a sequence constructor (a text value template:
  TextAvt) }
procedure TRun.DoText(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; R: TReceiver);
var
  S: TLandrixXmlUtf8;
begin
  if Instr.TextAvt <> nil then
    S := EvalAvt(Instr, Instr.TextAvt, Focus)
  else
    S := Instr.Text;
  if Instr.NoEscape then
    R.RawCharacters(S)
  else
    R.Characters(S);
end;

procedure TRun.DoVariable(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode);
begin
  FEvaluator.BindValue(Instr.Slot, VariableValue(Instr, Instr.BaseUri, Instr.Select, Instr.Body, Instr.HasAs, Instr.AsType,
    Instr.VarName, Focus, Mode));
end;

function TRun.Test(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus): Boolean;
begin
  Result := FEvaluator.EffectiveBoolean(Eval(Instr, Instr.Test, Focus));
end;

{ the branch of xsl:choose to run: its body (Instr.Body for otherwise) }
function TRun.ChosenBody(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus): TObjectList;
var
  I: Integer;
  W: TXsltInstr;
begin
  for I := 0 to Integer(Instr.Branches.Count) - 1 do
  begin
    W := TXsltInstr(Instr.Branches[I]);
    if Test(W, Focus) then
    begin
      Result := W.Body;
      Exit;
    end;
  end;
  Result := Instr.Body;
end;

{ The order of Items by the sort keys of Instr (XSLT 2.0 13.1): the keys
  are evaluated per item with the item, its position and the size as the
  focus (and with Groups the current group and key of the item, as
  xsl:for-each-group sorts its groups), the attributes once with Focus.
  An empty key comes first, then NaN; equal keys keep the order of Items
  (the sort is stable). }
function TRun.SortOrder(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  const Items: TLandrixXmlXPathSequence; const Groups, GroupKeys: TSequenceArray;
  HasKey: Boolean): TSortOrder;
var
  N, NK, I, K: Integer;
  Keys: array of TLandrixXmlXPathItems;
  Empty: array of array of Boolean;
  Descending: array of Boolean;
  CaseOrder, DataType: array of Integer;
  Key: TXsltSortKey;
  Where: TXsltInstr;
  V: TLandrixXmlXPathSequence;
  S: TLandrixXmlUtf8;
  Temp, Idx: TSortOrder;
  F: TLandrixXmlXPathFocus;
  SavedGroup, SavedKey: TLandrixXmlXPathSequence;
  SavedActive, SavedHasKey: Boolean;
  SavedLazy: Integer;

  function Compare(A, B: Integer): Integer;
  var
    J: Integer;
  begin
    Result := 0;
    for J := 0 to NK - 1 do
    begin
      if Empty[J][A] and Empty[J][B] then
        Result := 0
      else if Empty[J][A] then
        Result := -1
      else if Empty[J][B] then
        Result := 1
      else
        try
          Result := FEvaluator.SortCompare(Keys[J][A], Keys[J][B], CaseOrder[J]);
        except
          on E: ELandrixXmlXPathError do
            if E.XPathCode = 'XPTY0004' then
              Fail(TXsltSortKey(Instr.SortKeys[J]).Where, 'XTDE1030', 'sort keys that cannot be compared: ' +
                System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt))
            else
              Located(TXsltSortKey(Instr.SortKeys[J]).Where, E);
        end;
      if Descending[J] then
        Result := -Result;
      if Result <> 0 then
        Exit;
    end;
    Result := A - B;
  end;

  procedure MergeSort(Lo, Hi: Integer);
  var
    Mid, L, R2, T: Integer;
  begin
    if Hi - Lo < 1 then
      Exit;
    Mid := (Lo + Hi) div 2;
    MergeSort(Lo, Mid);
    MergeSort(Mid + 1, Hi);
    L := Lo;
    R2 := Mid + 1;
    T := Lo;
    while (L <= Mid) and (R2 <= Hi) do
    begin
      if Compare(Idx[L], Idx[R2]) <= 0 then
      begin
        Temp[T] := Idx[L];
        Inc(L);
      end
      else
      begin
        Temp[T] := Idx[R2];
        Inc(R2);
      end;
      Inc(T);
    end;
    while L <= Mid do
    begin
      Temp[T] := Idx[L];
      Inc(L);
      Inc(T);
    end;
    while R2 <= Hi do
    begin
      Temp[T] := Idx[R2];
      Inc(R2);
      Inc(T);
    end;
    for T := Lo to Hi do
      Idx[T] := Temp[T];
  end;

begin
  Idx := nil;
  Keys := nil;
  Empty := nil;
  Descending := nil;
  CaseOrder := nil;
  DataType := nil;
  Temp := nil;
  N := Items.Count;
  NK := Integer(Instr.SortKeys.Count);
  SetLength(Idx, N);
  for I := 0 to N - 1 do
    Idx[I] := I;
  SetLength(Keys, NK);
  SetLength(Empty, NK);
  SetLength(Descending, NK);
  SetLength(CaseOrder, NK);
  SetLength(DataType, NK);
  for K := 0 to NK - 1 do
  begin
    Key := TXsltSortKey(Instr.SortKeys[K]);
    Where := Key.Where;
    Descending[K] := False;
    if Key.Order <> nil then
    begin
      S := Trim8(EvalAvt(Where, Key.Order, Focus));
      if S = 'descending' then
        Descending[K] := True
      else if S <> 'ascending' then
        Fail(Where, 'XTDE0030', 'xsl:sort order is ascending or descending');
    end;
    CaseOrder[K] := 0;
    if Key.CaseOrder <> nil then
    begin
      S := Trim8(EvalAvt(Where, Key.CaseOrder, Focus));
      if S = 'upper-first' then
        CaseOrder[K] := 1
      else if S = 'lower-first' then
        CaseOrder[K] := -1
      else
        Fail(Where, 'XTDE0030', 'xsl:sort case-order is upper-first or lower-first');
    end;
    DataType[K] := 0;
    if Key.DataType <> nil then
    begin
      S := Trim8(EvalAvt(Where, Key.DataType, Focus));
      if S = 'text' then
        DataType[K] := 1
      else if S = 'number' then
        DataType[K] := 2
      else if Pos8(':', S) > 0 then
        raise ELandrixXmlXsltError.CreateXslt(xecUnsupported, 'FOER0000',
          'a data-type of xsl:sort with a prefix is not supported', Where.Module, Where.Line, Where.Column)
      else
        Fail(Where, 'XTDE0030', 'xsl:sort data-type is text, number or a prefixed name');
    end;
    if Key.Stable <> nil then
    begin
      { the sort is stable either way }
      S := Trim8(EvalAvt(Where, Key.Stable, Focus));
      if (S <> 'yes') and (S <> 'no') then
        Fail(Where, 'XTDE0030', 'xsl:sort stable is yes or no');
    end;
    if Key.Collation <> nil then
    begin
      CheckCollation(Where, Trim8(EvalAvt(Where, Key.Collation, Focus)), 'XTDE1035');
      { a collation given: case-order does not apply }
      CaseOrder[K] := 0;
    end;
    SetLength(Keys[K], N);
    SetLength(Empty[K], N);
  end;
  SavedGroup := FGroup;
  SavedKey := FGroupKey;
  SavedActive := FGroupActive;
  SavedLazy := FGroupLazyDepth;
  SavedHasKey := FGroupHasKey;
  try
    for I := 0 to N - 1 do
    begin
      F := ItemFocus(Items.Items[I], I + 1, N);
      if Groups <> nil then
      begin
        FGroup := Groups[I];
        FGroupKey := GroupKeys[I];
        FGroupActive := True;
        FGroupHasKey := HasKey;
        FGroupLazyDepth := FEvaluator.LazyDepth;
      end;
      for K := 0 to NK - 1 do
      begin
        Key := TXsltSortKey(Instr.SortKeys[K]);
        if Key.Select <> nil then
          V := Eval(Key.Where, Key.Select, F)
        else
          V := TemporarySequence(Key.Body, F, Mode);
        V := FEvaluator.DataOf(V);
        { backwards compatible mode: the first value }
        if (V.Count > 1) and Key.Where.Backwards then
          V := FirstOf(V);
        if V.Count > 1 then
          Fail(Key.Where, 'XTTE1020', 'a sort key is more than one value');
        if DataType[K] = 2 then
        begin
          { number(): NaN for none }
          if V.Count = 0 then
            V := LandrixXmlXPathStringItem('');
          Keys[K][I] := FEvaluator.NumberOf(V.Items[0]);
          Empty[K][I] := False;
        end
        else if (V.Count = 0) and (DataType[K] = 1) then
        begin
          { string(): the empty string for none }
          Keys[K][I] := LandrixXmlXPathStringItem('').Items[0];
          Empty[K][I] := False;
        end
        else if V.Count = 0 then
          Empty[K][I] := True
        else
        begin
          Empty[K][I] := False;
          if (DataType[K] = 1) or (V.Items[0].Kind = xikUntypedAtomic) then
            Keys[K][I] := LandrixXmlXPathStringItem(FEvaluator.ItemString(V.Items[0])).Items[0]
          else
            Keys[K][I] := V.Items[0];
        end;
      end;
    end;
  finally
    FGroup := SavedGroup;
    FGroupKey := SavedKey;
    FGroupActive := SavedActive;
    FGroupLazyDepth := SavedLazy;
    FGroupHasKey := SavedHasKey;
  end;
  SetLength(Temp, N);
  MergeSort(0, N - 1);
  Result := Idx;
end;

{ S in the order of the sort keys of Instr (S itself without keys) }
function TRun.Sorted(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  const S: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  Order: TSortOrder;
  I: Integer;
  SavedRule: TXsltRule;
begin
  Order := nil;
  if Instr.SortKeys = nil then
  begin
    Result := S;
    Exit;
  end;
  { no current template rule in the sort keys }
  SavedRule := FRule;
  FRule := nil;
  try
    Order := SortOrder(Instr, Focus, Mode, S, nil, nil, False);
  finally
    FRule := SavedRule;
  end;
  Result := LandrixXmlXPathEmpty;
  for I := 0 to Integer(Length(Order)) - 1 do
    LandrixXmlXPathAppend(Result, S.Items[Order[I]]);
end;

procedure TRun.DoPerformSort(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  R: TReceiver);
var
  S: TLandrixXmlXPathSequence;
  I: Integer;
begin
  if Instr.Select <> nil then
    S := Eval(Instr, Instr.Select, Focus)
  else
    S := BodySequence(Instr.Body, Instr.BaseUri, Focus, Mode);
  S := Sorted(Instr, Focus, Mode, S);
  for I := 0 to Integer(S.Count) - 1 do
    R.Item(S.Items[I], False);
end;

{ xsl:analyze-string (XSLT 2.0 15.1): the string split into the matches
  and the substrings between them (empty ones dropped); each runs its
  body with the substring as the context item, its position among all of
  them and their number, and for a match the groups regex-group() gives }
procedure TRun.DoAnalyzeString(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  R: TReceiver);
var
  S, Pattern, Flags: TLandrixXmlUtf8;
  V: TLandrixXmlXPathSequence;
  Regex: TLandrixXmlRegex;
  Text, Found, Groups: TLandrixXmlCodePoints;
  Slots, Count, Position, I, J, Last, SavedLazy: Integer;
  SavedText, SavedGroups: TLandrixXmlCodePoints;
  SavedActive: Boolean;

  procedure Piece(Lo, Hi: Integer; Match: Boolean);
  var
    Body: TObjectList;
  begin
    Inc(Position);
    if Match then
      Body := Instr.Body
    else
      Body := Instr.NonMatching;
    FRegexActive := Match;
    FRegexLazyDepth := FEvaluator.LazyDepth;
    if Body <> nil then
      Exec(Body, ItemFocus(LandrixXmlXPathStringItem(LandrixXmlCodePointsToUtf8(Text, Lo, Hi)).Items[0],
        Position, Count), Mode, R);
  end;

begin
  Text := nil;
  Found := nil;
  Groups := nil;
  { xs:string? by the function conversion rules (an empty sequence as the
    empty string, as in Saxon; XSLT 2.0 makes it XPTY0004) }
  V := FEvaluator.ConvertSequence(Eval(Instr, Instr.Select, Focus), FOptionalStringType,
    'xsl:analyze-string select');
  S := '';
  if V.Count = 1 then
    S := FEvaluator.ItemString(V.Items[0]);
  Pattern := EvalAvt(Instr, Instr.RegexAvt, Focus);
  Flags := '';
  if Instr.FlagsAvt <> nil then
    Flags := EvalAvt(Instr, Instr.FlagsAvt, Focus);
  { a computed regex or flags that are invalid: FORX0002 and FORX0001 as
    in Saxon (XSLT 2.0 says XTDE1140 and XTDE1145, as for literal ones) }
  Regex := nil;
  try
    Regex := FEvaluator.CompiledRegex(Pattern, Flags, False);
  except
    on E: ELandrixXmlXPathError do
      Located(Instr, E);
  end;
  { XSLT 2.0: an error (Saxon accepts it with the rules of XSLT 3.0) }
  if Regex.MatchesEmptyString then
    Fail(Instr, 'XTDE1150', 'the regular expression matches a zero-length string');
  Found := Regex.Analyze(S, Text);
  Slots := 2 * (Regex.GroupCount + 1);
  { the number of pieces: the matches and the substrings before, between
    and after them that are not empty }
  Count := 0;
  Last := 0;
  I := 0;
  while I < Length(Found) do
  begin
    if Found[I] > Last then
      Inc(Count);
    Inc(Count);
    Last := Found[I + 1];
    Inc(I, Slots);
  end;
  if Length(Text) > Last then
    Inc(Count);
  SavedText := FRegexText;
  SavedGroups := FRegexGroups;
  SavedActive := FRegexActive;
  SavedLazy := FRegexLazyDepth;
  try
    FRegexText := Text;
    SetLength(Groups, Slots);
    Position := 0;
    Last := 0;
    I := 0;
    while I < Length(Found) do
    begin
      if Found[I] > Last then
        Piece(Last, Found[I], False);
      for J := 0 to Slots - 1 do
        Groups[J] := Found[I + J];
      FRegexGroups := Groups;
      Piece(Found[I], Found[I + 1], True);
      { a copy per match: a body may have kept nothing of it, but
        nested instructions replace the fields }
      Groups := nil;
      SetLength(Groups, Slots);
      Last := Found[I + 1];
      Inc(I, Slots);
    end;
    if Length(Text) > Last then
      Piece(Last, Integer(Length(Text)), False);
  finally
    FRegexText := SavedText;
    FRegexGroups := SavedGroups;
    FRegexActive := SavedActive;
    FRegexLazyDepth := SavedLazy;
  end;
end;

{ MatchesPattern without the captured substrings of xsl:analyze-string:
  regex-group() is empty in a pattern }
function TRun.PatternMatches(Expr: TLandrixXmlXPathExpression; Node: Integer; Relative: Boolean): Boolean;
var
  Saved: Boolean;
begin
  Saved := FRegexActive;
  FRegexActive := False;
  try
    Result := FEvaluator.MatchesPattern(Expr, Node, Relative);
  finally
    FRegexActive := Saved;
  end;
end;

{ regex-group(N): group N of the current match ('' if there is none, N
  is out of range or the group did not take part) }
function TRun.RegexGroup(const Arg: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  V: TLandrixXmlXPathSequence;
  N: Int64;
begin
  Result := LandrixXmlXPathStringItem('');
  V := FEvaluator.ConvertSequence(Arg, FIntegerType, 'regex-group()');
  if not FRegexActive or (FEvaluator.LazyDepth <> FRegexLazyDepth) or (V.Count = 0) then
    Exit;
  N := V.Items[0].Bits;
  { N checked before it is doubled (no overflow) }
  if (V.Items[0].Payload <> nil) or (N < 0) or (N >= Length(FRegexGroups) div 2) or
    (FRegexGroups[2 * N] < 0) or (FRegexGroups[2 * N + 1] < 0) then
    Exit;
  Result := LandrixXmlXPathStringItem(LandrixXmlCodePointsToUtf8(FRegexText, FRegexGroups[2 * N],
    FRegexGroups[2 * N + 1]));
end;

procedure TRun.DoForEach(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  S: TLandrixXmlXPathSequence;
  I: Integer;
begin
  S := Sorted(Instr, Focus, Mode, Eval(Instr, Instr.Select, Focus));
  for I := 0 to Integer(S.Count) - 1 do
    Exec(Instr.Body, ItemFocus(S.Items[I], I + 1, S.Count), Mode, R);
end;

procedure TRun.DoSequence(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; R: TReceiver);
var
  S: TLandrixXmlXPathSequence;
  I: Integer;
  Saved: Boolean;
begin
  S := Eval(Instr, Instr.Select, Focus);
  if R is TSequenceReceiver then
    TSequenceReceiver(R).CopyBase := Instr.BaseUri;
  Saved := FNoNamespaces;
  FNoNamespaces := Instr.NoNamespaces;
  try
    for I := 0 to Integer(S.Count) - 1 do
      R.Item(S.Items[I], Instr.Kind = xskCopyOf);
  finally
    FNoNamespaces := Saved;
  end;
end;

procedure TRun.DoElement(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  Uri, Prefix, Local: TLandrixXmlUtf8;
begin
  ComputedName(Instr, Focus, True, Uri, Prefix, Local);
  if R is TSequenceReceiver then
    TSequenceReceiver(R).SetNextBase(Instr.BaseUri);
  R.StartElement(Uri, Prefix, Local);
  if Instr.UseSets <> nil then
    DoUseAttributeSets(Instr.UseSets, Focus, Mode, R);
  Exec(Instr.Body, Focus, Mode, R);
  R.EndElement;
end;

procedure TRun.DoAttribute(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  Uri, Prefix, Local, Text, Sep: TLandrixXmlUtf8;
begin
  ComputedName(Instr, Focus, False, Uri, Prefix, Local);
  if Instr.Select <> nil then
    Sep := ' '
  else
    Sep := '';
  if Instr.Separator <> nil then
    Sep := EvalAvt(Instr, Instr.Separator, Focus);
  if Instr.Select <> nil then
    Text := EvalString(Instr, Instr.Select, Focus, Sep)
  else
    Text := BodyString(Instr.Body, Focus, Mode, Sep);
  R.Attribute(Uri, Prefix, Local, Text);
end;

{ the text of xsl:comment and xsl:processing-instruction (the separator
  is a space for select and body alike) }
function TRun.InstrText(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode): TLandrixXmlUtf8;
begin
  if Instr.Select <> nil then
    Result := EvalString(Instr, Instr.Select, Focus, ' ')
  else
    Result := BodyString(Instr.Body, Focus, Mode, ' ');
end;

procedure TRun.DoProcessingInstruction(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  R: TReceiver);
var
  Local: TLandrixXmlUtf8;
begin
  Local := EvalAvt(Instr, Instr.NameAvt, Focus);
  if not IsNCName8(Local) or (LowerCase(LandrixXmlUtf8ToString(Local)) = 'xml') then
    Fail(Instr, 'XTDE0890', 'not a valid processing instruction name: "' + LandrixXmlUtf8ToString(Local) + '"');
  R.ProcessingInstruction(Local, PIText(InstrText(Instr, Focus, Mode)));
end;

procedure TRun.DoMessage(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode);
var
  Text, Terminate: TLandrixXmlUtf8;
begin
  Terminate := 'no';
  { checked before the content runs (Saxon) }
  if Instr.NameAvt <> nil then
  begin
    { yes or no, white space trimmed (true, false, 1 and 0 as Saxon) }
    Terminate := Trim8(EvalAvt(Instr, Instr.NameAvt, Focus));
    if (Terminate = 'true') or (Terminate = '1') then
      Terminate := 'yes'
    else if (Terminate = 'false') or (Terminate = '0') then
      Terminate := 'no';
    if (Terminate <> 'yes') and (Terminate <> 'no') then
      Fail(Instr, 'XTDE0030', 'xsl:message: terminate must be yes or no');
  end;
  Text := FEvaluator.ItemString(ContentDocument(Instr, Focus, Mode).Items[0]);
  FSettings.Messages.Add(TLandrixXmlXsltMessage.Create(Text, Terminate = 'yes', Instr.Module, Instr.Line,
    Instr.Column));
  if Terminate = 'yes' then
    Fail(Instr, 'XTMM9000', 'terminated by xsl:message: ' + LandrixXmlUtf8ToString(Text));
end;

procedure TRun.DoDocument(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  Doc: TLandrixXmlXPathSequence;
begin
  FDocumentRaw := True;
  Doc := BodyDocument(Instr.Body, Instr.BaseUri, Focus, Mode);
  R.Item(Doc.Items[0], False);
end;

procedure TRun.DoApplyTemplates(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  R: TReceiver);
var
  M: TXsltMode;
  S: TLandrixXmlXPathSequence;
  Params, Tunnel, Saved: TSuppliedArray;
begin
  M := TXsltMode(Instr.Mode);
  if Instr.CurrentMode then
    M := Mode;
  S := Sorted(Instr, Focus, Mode, Eval(Instr, Instr.Select, Focus));
  Params := Supplied(Instr, Focus, Mode);
  Tunnel := Tunnelled(Instr, Focus, Mode);
  Saved := FTunnel;
  FTunnel := Tunnel;
  try
    ApplyTemplates(Instr, S, M, Params, R);
  finally
    FTunnel := Saved;
  end;
end;

{ the attributes of the attribute sets: each declaration with the focus,
  the mode and the current template rule of the instruction that uses it
  (its own attribute sets first, then its xsl:attribute instructions) }
procedure TRun.DoUseAttributeSets(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  R: TReceiver);
var
  I: Integer;
begin
  for I := 0 to Integer(Instr.Sets.Count) - 1 do
    Invoke(TXsltTemplate(Instr.Sets[I]), Focus, Mode, nil, R);
end;

{ xsl:namespace: a namespace node of the element being built; the prefix
  and the URI without surrounding white space (Saxon) }
procedure TRun.DoNamespace(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  R: TReceiver);
var
  Prefix, Uri: TLandrixXmlUtf8;
begin
  Prefix := Trim8(EvalAvt(Instr, Instr.NameAvt, Focus));
  if (Prefix <> '') and (not IsNCName8(Prefix) or (Prefix = 'xmlns')) then
    Fail(Instr, 'XTDE0920', 'not a valid namespace prefix: "' + LandrixXmlUtf8ToString(Prefix) + '"');
  if Instr.Select <> nil then
    Uri := EvalString(Instr, Instr.Select, Focus, ' ')
  else
    Uri := BodyString(Instr.Body, Focus, Mode, ' ');
  Uri := Trim8(Uri);
  if Uri = '' then
    Fail(Instr, 'XTDE0930', 'the namespace URI of xsl:namespace is empty');
  if (Prefix = 'xml') <> (Uri = LandrixXmlNamespaceXml) then
    Fail(Instr, 'XTDE0925', 'the prefix xml and the namespace ' + LandrixXmlUtf8ToString(LandrixXmlNamespaceXml) +
      ' belong together');
  if Uri = 'http://www.w3.org/2000/xmlns/' then
    Fail(Instr, 'XTDE0905', 'the namespace http://www.w3.org/2000/xmlns/ cannot be bound');
  try
    R.NamespaceNode(Prefix, Uri);
  except
    on E: ELandrixXmlXsltError do
      raise;
    on E: ELandrixXmlXPathError do
      Fail(Instr, E.XPathCode, System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt));
  end;
end;

procedure TRun.DoCallTemplate(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  R: TReceiver);
var
  Params, Tunnel, Saved: TSuppliedArray;
begin
  Params := Supplied(Instr, Focus, Mode);
  Tunnel := Tunnelled(Instr, Focus, Mode);
  Saved := FTunnel;
  FTunnel := Tunnel;
  try
    Invoke(TXsltTemplate(Instr.Template), Focus, Mode, Params, R);
  finally
    FTunnel := Saved;
  end;
end;

{ Whether Node matches the count pattern (Count) or the from pattern of
  xsl:number; without a count pattern: a node of the kind and name of
  Model. }
function TRun.NumberMatches(Instr: TXsltInstr; Count: Boolean; Node, Model: Integer): Boolean;
var
  I, B, BM: Integer;
  T, TM: TLandrixXmlXPathTree;
begin
  Result := False;
  if Count and (Length(Instr.CountPatterns) = 0) then
  begin
    T := FEvaluator.TreeOfNode(Node, B);
    TM := FEvaluator.TreeOfNode(Model, BM);
    Result := (T.Kind[Node - B] = TM.Kind[Model - BM]) and
      (T.LocalNameUtf8(Node - B) = TM.LocalNameUtf8(Model - BM)) and
      (T.NamespaceUriUtf8(Node - B) = TM.NamespaceUriUtf8(Model - BM));
    Exit;
  end;
  FEvaluator.CurrentNode := Node;
  FCurrent := LandrixXmlXPathEmpty;
  if Count then
  begin
    for I := 0 to Integer(Length(Instr.CountPatterns)) - 1 do
      if PatternMatches(Instr.CountPatterns[I], Node, Instr.CountRelative[I]) then
      begin
        Result := True;
        Exit;
      end;
  end
  else
    for I := 0 to Integer(Length(Instr.FromPatterns)) - 1 do
      if PatternMatches(Instr.FromPatterns[I], Node, Instr.FromRelative[I]) then
      begin
        Result := True;
        Exit;
      end;
end;

{ The text of one number in a format token: decimal digits (their number
  the minimum width), a, A, i, I, English words (W, w, Ww). Ordinal: an
  ordinal (digits and words; Saxon ignores it for letters and roman
  numerals); Alphabetic: letter-value="alphabetic", i and I are letters
  from i to z (as Saxon). }
function NumberToken(N: Integer; const Token: TLandrixXmlUtf8; const GroupSep: TLandrixXmlUtf8;
  GroupSize: Integer; Ordinal, Alphabetic: Boolean): TLandrixXmlUtf8;
const
  Values: array[0..12] of Integer = (1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1);
  Symbols: array[0..12] of string = ('M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I');
var
  I, K, Width: Integer;
  Digits: Boolean;
  S, Letters: TLandrixXmlUtf8;
begin
  Result := '';
  if (Token = 'W') or (Token = 'w') or (Token = 'Ww') then
  begin
    Result := XPathWordsCase(XPathNumberWords(N, Ordinal), Token);
    Exit;
  end;
  if Alphabetic and ((Token = 'i') or (Token = 'I')) then
  begin
    Result := XPathLetters(N, Token[1]);
    Exit;
  end;
  Letters := 'abcdefghijklmnopqrstuvwxyz';
  if Token = 'A' then
    Letters := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  if (Token = 'a') or (Token = 'A') then
  begin
    K := N;
    while K > 0 do
    begin
      Dec(K);
      Result := Copy(Letters, K mod 26 + 1, 1) + Result;
      K := K div 26;
    end;
    if Result = '' then
      Result := '0';
    Exit;
  end;
  if (Token = 'i') or (Token = 'I') then
  begin
    K := N;
    if (K <= 0) or (K > 9999) then
      Result := LandrixXmlStringToUtf8(IntToStr(K))
    else
      for I := 0 to 12 do
        while K >= Values[I] do
        begin
          Result := Result + LandrixXmlStringToUtf8(Symbols[I]);
          Dec(K, Values[I]);
        end;
    if Token = 'i' then
      Result := LandrixXmlStringToUtf8(LowerCase(LandrixXmlUtf8ToString(Result)));
    Exit;
  end;
  Digits := Token <> '';
  for I := 1 to Length(Token) do
    if not (Token[I] in ['0'..'9']) then
      Digits := False;
  if not Digits then
    raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT: the xsl:number format token "' +
      LandrixXmlUtf8ToString(Token) + '" is not supported');
  Width := Length(Token);
  Result := LandrixXmlStringToUtf8(IntToStr(N));
  while Length(Result) < Width do
    Result := '0' + Result;
  if (GroupSep <> '') and (GroupSize > 0) then
  begin
    S := '';
    K := 0;
    for I := Length(Result) downto 1 do
    begin
      if (K > 0) and (K mod GroupSize = 0) then
        S := GroupSep + S;
      S := Copy(Result, I, 1) + S;
      Inc(K);
    end;
    Result := S;
  end;
  if Ordinal then
    Result := Result + XPathOrdinalSuffix(N);
end;

{ Numbers formatted as XSLT 2.0 12.3 says: the alphanumeric tokens of the
  format and the separators between them (prefix and suffix kept; the
  last token and separator for further numbers). }
function FormatNumbers(const Numbers: array of Integer; const Format, GroupSep: TLandrixXmlUtf8;
  GroupSize: Integer; Ordinal, Alphabetic: Boolean): TLandrixXmlUtf8;
var
  Tokens, Seps: TLandrixXmlUtf8Array;
  Prefix, Suffix, Sep, Token: TLandrixXmlUtf8;
  I, Start, K: Integer;

  function Alnum(C: AnsiChar): Boolean;
  begin
    Result := C in ['0'..'9', 'A'..'Z', 'a'..'z'];
  end;

begin
  Tokens := nil;
  Seps := nil;
  Prefix := '';
  Suffix := '';
  for I := 1 to Length(Format) do
    if Ord(Format[I]) >= $80 then
      raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT: an xsl:number format with characters ' +
        'other than ASCII is not supported');
  I := 1;
  while (I <= Length(Format)) and not Alnum(Format[I]) do
    Inc(I);
  Prefix := Copy(Format, 1, I - 1);
  while I <= Length(Format) do
  begin
    Start := I;
    while (I <= Length(Format)) and Alnum(Format[I]) do
      Inc(I);
    K := Integer(Length(Tokens));
    SetLength(Tokens, K + 1);
    Tokens[K] := Copy(Format, Start, I - Start);
    Start := I;
    while (I <= Length(Format)) and not Alnum(Format[I]) do
      Inc(I);
    if I > Length(Format) then
      Suffix := Copy(Format, Start, I - Start)
    else
    begin
      SetLength(Seps, K + 1);
      Seps[K] := Copy(Format, Start, I - Start);
    end;
  end;
  if Length(Tokens) = 0 then
  begin
    { no token: "1", the format before and after it }
    SetLength(Tokens, 1);
    Tokens[0] := '1';
    Suffix := Prefix;
  end;
  Result := Prefix;
  for I := 0 to Integer(High(Numbers)) do
  begin
    if I > 0 then
    begin
      if I - 1 < Length(Seps) then
        Sep := Seps[I - 1]
      else if Length(Seps) > 0 then
        Sep := Seps[High(Seps)]
      else
        Sep := '.';
      Result := Result + Sep;
    end;
    if I < Length(Tokens) then
      Token := Tokens[I]
    else
      Token := Tokens[High(Tokens)];
    if Numbers[I] < 0 then
      Result := Result + 'NaN'
    else
      Result := Result + NumberToken(Numbers[I], Token, GroupSep, GroupSize, Ordinal, Alphabetic);
  end;
  Result := Result + Suffix;
end;

procedure TRun.DoNumber(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; R: TReceiver);
var
  Numbers: array of Integer;
  S: TLandrixXmlXPathSequence;
  T: TLandrixXmlXPathTree;
  Node, B, I, A, C, K: Integer;
  GroupSep, V: TLandrixXmlUtf8;
  GroupSize: Integer;
  Big: Int64;
  Chain: array of Integer;
  Ordinal, Alphabetic, FromFound: Boolean;

  procedure Add(N: Integer);
  begin
    SetLength(Numbers, Length(Numbers) + 1);
    Numbers[High(Numbers)] := N;
  end;

  { 1 + the preceding siblings of Node that match the count pattern }
  function SiblingNumber(N: Integer): Integer;
  var
    P, X: Integer;
  begin
    Result := 1;
    if T.Kind[N - B] = xnkAttribute then
      Exit;
    P := T.Parent[N - B];
    if P < 0 then
      Exit;
    X := T.FirstChild(P);
    while (X >= 0) and (X <> N - B) do
    begin
      if NumberMatches(Instr, True, X + B, Node) then
        Inc(Result);
      X := T.NextSibling[X];
    end;
  end;

begin
  Numbers := nil;
  Chain := nil;
  { lang, ordinal and letter-value first (Saxon: a bad lang before an
    empty select). Saxon HE numbers in English whatever the language;
    any ordinal value but the empty string is an ordinal. }
  if (Instr.NumberLang <> nil) and not XPathIsLanguage(Trim8(EvalAvt(Instr, Instr.NumberLang, Focus))) then
    Fail(Instr, 'XTDE0030', 'xsl:number: lang must be a language code');
  Ordinal := (Instr.NumberOrdinal <> nil) and (EvalAvt(Instr, Instr.NumberOrdinal, Focus) <> '');
  Alphabetic := False;
  if Instr.LetterValue <> nil then
  begin
    V := EvalAvt(Instr, Instr.LetterValue, Focus);
    if (V <> 'alphabetic') and (V <> 'traditional') then
      Fail(Instr, 'XTDE0030', 'xsl:number: letter-value must be alphabetic or traditional');
    Alphabetic := V = 'alphabetic';
  end;
  if Instr.NumberValue <> nil then
  begin
    S := Eval(Instr, Instr.NumberValue, Focus);
    { backwards compatible mode: the first item, NaN for none }
    if Instr.Backwards then
    begin
      S := FirstOf(S);
      if S.Count = 0 then
        S := LandrixXmlXPathStringItem('NaN');
    end;
    for I := 0 to Integer(S.Count) - 1 do
    begin
      { round(number(.)), -1 for NaN }
      K := StrToIntDef(LandrixXmlUtf8ToString(FEvaluator.ItemString(FEvaluator.EvaluateInFocus(FRoundExpr,
        ItemFocus(S.Items[I], 1, 1)).Items[0])), -1);
      if (K = -2) and Instr.Backwards and (FEvaluator.DataOf(FirstOf(S)).Count = 1) and
        (FEvaluator.ItemString(FEvaluator.NumberOf(FEvaluator.DataOf(FirstOf(S)).Items[0])) = 'INF') then
        K := -1;
      if K = -2 then
        raise ELandrixXmlXsltError.CreateXslt(xecUnsupported, 'FOER0000', 'xsl:number: a value above ' +
          IntToStr(MaxInt) + ' is not supported', Instr.Module, Instr.Line, Instr.Column);
      { backwards compatible mode: NaN, a negative number and infinity
        are formatted as NaN (-1 here), as Saxon }
      if (K < 0) and Instr.Backwards then
        K := -1
      else if K < 0 then
        Fail(Instr, 'XTDE0980', 'xsl:number: ' + LandrixXmlUtf8ToString(FEvaluator.ItemString(S.Items[I])) +
          ' is no number from 0 on');
      Add(K);
    end;
  end
  else
  begin
    if Instr.Select <> nil then
    begin
      S := Eval(Instr, Instr.Select, Focus);
      if (S.Count <> 1) or (S.Items[0].Kind <> xikNode) then
        Fail(Instr, 'XTTE1000', 'xsl:number: select must give one node');
      Node := S.Items[0].Node;
    end
    else
    begin
      if Focus.Node < 0 then
        Fail(Instr, 'XTTE0990', 'xsl:number: the context item is no node');
      Node := Focus.Node;
    end;
    T := FEvaluator.TreeOfNode(Node, B);
    case Instr.NumberLevel of
      0, 1:
        begin
          { the ancestors-or-self that match count, up to one that matches from }
          A := Node - B;
          while A >= 0 do
          begin
            if NumberMatches(Instr, True, A + B, Node) then
            begin
              SetLength(Chain, Length(Chain) + 1);
              Chain[High(Chain)] := A + B;
              if Instr.NumberLevel = 0 then
                Break;
            end;
            if (Length(Instr.FromPatterns) > 0) and NumberMatches(Instr, False, A + B, Node) then
              Break;
            A := T.Parent[A];
          end;
          { level="single" with count and from (Saxon): the counted node
            needs an ancestor-or-self that matches from, the root is no
            fallback (without count it is, as in the specification) }
          if (Instr.NumberLevel = 0) and (Length(Instr.FromPatterns) > 0) and
            (Length(Instr.CountPatterns) > 0) and (Length(Chain) > 0) then
          begin
            FromFound := False;
            A := Chain[0] - B;
            while (A >= 0) and not FromFound do
            begin
              FromFound := NumberMatches(Instr, False, A + B, Node);
              A := T.Parent[A];
            end;
            if not FromFound then
              Chain := nil;
          end;
          for I := Integer(High(Chain)) downto 0 do
            Add(SiblingNumber(Chain[I]));
        end;
    else
      begin
        { the nodes before Node (not attributes) and its ancestors-or-self
          that match count, after the last one that matches from }
        C := 0;
        for K := 0 to Node - B do
        begin
          if (T.Kind[K] = xnkAttribute) and (K <> Node - B) then
            Continue;
          if (Length(Instr.FromPatterns) > 0) and NumberMatches(Instr, False, K + B, Node) then
            C := 0;
          if NumberMatches(Instr, True, K + B, Node) then
            Inc(C);
        end;
        if C > 0 then
          Add(C);
      end;
    end;
  end;
  GroupSep := '';
  GroupSize := 0;
  if (Instr.GroupingSeparator <> nil) and (Instr.GroupingSize <> nil) then
  begin
    GroupSep := EvalAvt(Instr, Instr.GroupingSeparator, Focus);
    { an integer, a sign allowed; 0 or less: no grouping (as Saxon) }
    V := EvalAvt(Instr, Instr.GroupingSize, Focus);
    A := 1;
    if (V <> '') and ((V[1] = '-') or (V[1] = '+')) then
      A := 2;
    if A > Length(V) then
      Fail(Instr, 'XTDE0030', 'xsl:number: grouping-size must be an integer');
    { in the range of a 32-bit integer (Saxon: XTDE0030 beyond it) }
    Big := 0;
    for I := A to Length(V) do
      if not (V[I] in ['0'..'9']) then
        Fail(Instr, 'XTDE0030', 'xsl:number: grouping-size must be an integer')
      else if Big <= 2147483648 then
        Big := Big * 10 + Ord(V[I]) - Ord('0');
    if (Big > 2147483648) or ((Big = 2147483648) and (V[1] <> '-')) then
      Fail(Instr, 'XTDE0030', 'xsl:number: grouping-size must be an integer');
    GroupSize := 0;
    if (A = 1) or (V[1] = '+') then
      GroupSize := Integer(Big);
  end;
  R.Characters(FormatNumbers(Numbers, EvalAvt(Instr, Instr.FormatAvt, Focus), GroupSep, GroupSize, Ordinal,
    Alphabetic));
end;

{ whether Href can name a text resource: no fragment, no query, none of
  the ASCII characters a URI may not hold, a backslash included (Saxon:
  FOUT1170) }
function UriTextOk(const Href: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to Length(Href) do
    if (Href[I] < '!') or (Href[I] in ['#', '?', '"', '<', '>', '|', '{', '}', '^', '`', '\']) then
      Exit;
  Result := True;
end;

{ the rest of Content as bytes; frees Content }
function ReadAndFree(Content: TStream): TLandrixXmlUtf8;
var
  Len: Integer;
begin
  Result := '';
  try
    Len := Integer(Content.Size - Content.Position);
    SetLength(Result, Len);
    if Len > 0 then
      Content.ReadBuffer(PAnsiChar(Result)^, Len);
  finally
    Content.Free;
  end;
end;

{ appends the code point C to Text in UTF-8; False if it is none }
function AddCodePoint(var Text: TLandrixXmlUtf8; C: Cardinal): Boolean;
var
  Buf: array[0..3] of AnsiChar;
  K: Integer;
begin
  K := LandrixXmlEncodeUtf8(C, @Buf[0]);
  Result := K > 0;
  if Result then
    Text := Text + LandrixXmlBufToUtf8(@Buf[0], K);
end;

{ appends the UTF-16 of Raw from byte I on (little or big endian) to Text;
  False for a byte sequence that is no UTF-16 }
function DecodeUtf16(const Raw: TLandrixXmlUtf8; I: Integer; Little: Boolean;
  var Text: TLandrixXmlUtf8): Boolean;
var
  W, W2: Cardinal;
begin
  Result := False;
  while I + 1 <= Length(Raw) do
  begin
    if Little then
      W := Ord(Raw[I]) or (Ord(Raw[I + 1]) shl 8)
    else
      W := (Ord(Raw[I]) shl 8) or Ord(Raw[I + 1]);
    Inc(I, 2);
    if (W >= $D800) and (W < $DC00) then
    begin
      if I + 1 > Length(Raw) then
        Exit;
      if Little then
        W2 := Ord(Raw[I]) or (Ord(Raw[I + 1]) shl 8)
      else
        W2 := (Ord(Raw[I]) shl 8) or Ord(Raw[I + 1]);
      Inc(I, 2);
      if (W2 < $DC00) or (W2 > $DFFF) then
        Exit;
      W := $10000 + ((W - $D800) shl 10) + (W2 - $DC00);
    end
    else if (W >= $DC00) and (W <= $DFFF) then
      Exit;
    if not AddCodePoint(Text, W) then
      Exit;
  end;
  Result := I > Length(Raw);
end;

{ unparsed-text() and unparsed-text-available(): a text resource through
  the resolver (xrkText), relative to the module; UTF-8, UTF-16 and
  ISO-8859-1. Without an encoding a byte order mark decides (else UTF-8)
  and bytes not in it are FOUT1200; with one given (as Saxon) they are
  FOUT1190. FOUT1190 for characters that are no XML characters }
function TRun.UnparsedText(Kind: Integer; const Base: TLandrixXmlUtf8;
  const HrefArg, EncodingArg: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  Href, Encoding, Uri, Raw, Text: TLandrixXmlUtf8;
  Available, Given: Boolean;
  Content: TStream;
  N, I: Integer;
  Code: Cardinal;
  Error: string;
  Enc: string;
begin
  Result := LandrixXmlXPathEmpty;
  Available := Kind >= XfnUnparsedTextAvailable1;
  { the encoding is one string (also when the URI is empty) }
  Given := (Kind = XfnUnparsedText2) or (Kind = XfnUnparsedTextAvailable2);
  Encoding := '';
  if Given then
    Encoding := FEvaluator.ItemString(FEvaluator.ConvertSequence(EncodingArg, FStringType, 'unparsed-text()').Items[0]);
  if HrefArg.Count = 0 then
  begin
    if Available then
      Result := FEvaluator.EvaluateInFocus(FFalse, NoFocus);
    Exit;
  end;
  Href := FEvaluator.ItemString(FEvaluator.ConvertSequence(HrefArg, FStringType, 'unparsed-text()').Items[0]);
  { the names Saxon (Java) takes, not trimmed }
  Enc := LowerCase(LandrixXmlUtf8ToString(Encoding));
  if Given and (Enc <> 'utf-8') and (Enc <> 'utf8') and (Enc <> 'utf-16') and (Enc <> 'utf16') and
    (Enc <> 'utf-16le') and (Enc <> 'utf-16be') and (Enc <> 'iso-8859-1') and (Enc <> 'latin1') and
    (Enc <> 'iso8859-1') then
  begin
    { not available in another encoding (it is not supported) }
    if Available then
    begin
      Result := FEvaluator.EvaluateInFocus(FFalse, NoFocus);
      Exit;
    end;
    raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT: unparsed-text() in the encoding ' +
      LandrixXmlUtf8ToString(Encoding) + ' is not supported');
  end;
  Error := '';
  Raw := '';
  Content := nil;
  { a fragment, a query or a character not allowed in a URI: no resource
    (Saxon) }
  if not UriTextOk(Href) or not OpenResource(xrkText, Base, Href, Uri, Content) then
    Error := 'FOUT1170'
  else
    Raw := ReadAndFree(Content);
  Text := '';
  if Error = '' then
  begin
    { without an encoding: a byte order mark, else UTF-8; an encoding
      given is used as it is (a byte order mark only for UTF-16 without
      an order), a leading U+FEFF is dropped afterwards (Saxon) }
    I := 1;
    if not Given and (Length(Raw) >= 3) and (Raw[1] = #$EF) and (Raw[2] = #$BB) and (Raw[3] = #$BF) then
    begin
      Enc := 'utf-8';
      I := 4;
    end
    else if (not Given or (Enc = 'utf-16') or (Enc = 'utf16')) and (Length(Raw) >= 2) and
      (Raw[1] = #$FF) and (Raw[2] = #$FE) then
    begin
      Enc := 'utf-16le';
      I := 3;
    end
    else if (not Given or (Enc = 'utf-16') or (Enc = 'utf16')) and (Length(Raw) >= 2) and
      (Raw[1] = #$FE) and (Raw[2] = #$FF) then
    begin
      Enc := 'utf-16be';
      I := 3;
    end
    else if not Given then
      Enc := 'utf-8';
    if Enc = 'utf-16le' then
    begin
      if not DecodeUtf16(Raw, I, True, Text) then
        Error := 'FOUT1200';
    end
    else if (Enc = 'utf-16') or (Enc = 'utf16') or (Enc = 'utf-16be') then
    begin
      if not DecodeUtf16(Raw, I, False, Text) then
        Error := 'FOUT1200';
    end
    else if (Enc = 'utf-8') or (Enc = 'utf8') then
    begin
      Text := Copy(Raw, I, MaxInt);
      I := 1;
      while (Error = '') and (I <= Length(Text)) do
      begin
        N := LandrixXmlDecodeUtf8(PAnsiChar(Text) + I - 1, Length(Text) - I + 1, Code);
        if N = 0 then
          Error := 'FOUT1200'
        else
          Inc(I, N);
      end;
    end
    else
      { ISO-8859-1: each byte is its code point }
      while I <= Length(Raw) do
      begin
        AddCodePoint(Text, Ord(Raw[I]));
        Inc(I);
      end;
    if Given and (Error = '') and (Length(Text) >= 3) and (Text[1] = #$EF) and (Text[2] = #$BB) and
      (Text[3] = #$BF) then
      Delete(Text, 1, 3);
    { bytes not in an encoding given: FOUT1190 (Saxon) }
    if Given and (Error = 'FOUT1200') then
      Error := 'FOUT1190';
    { XML characters only }
    I := 1;
    while (Error = '') and (I <= Length(Text)) do
    begin
      N := LandrixXmlDecodeUtf8(PAnsiChar(Text) + I - 1, Length(Text) - I + 1, Code);
      if N = 0 then
      begin
        Error := 'FOUT1200';
        Break;
      end;
      if (Code < 32) and (Code <> 9) and (Code <> 10) and (Code <> 13) or (Code = $FFFE) or (Code = $FFFF) then
        Error := 'FOUT1190';
      Inc(I, N);
    end;
  end;
  if Available then
  begin
    if Error <> '' then
      Result := FEvaluator.EvaluateInFocus(FFalse, NoFocus)
    else
      Result := FEvaluator.EvaluateInFocus(FTrue, NoFocus);
  end
  else if Error = 'FOUT1170' then
    raise ELandrixXmlXPathError.CreateXPath('FOUT1170', 'unparsed-text(): ' + LandrixXmlUtf8ToString(Href) +
      ' is not available')
  else if Error <> '' then
    raise ELandrixXmlXPathError.CreateXPath(Error, 'unparsed-text(): ' + LandrixXmlUtf8ToString(Href) +
      ' is not text of XML characters in its encoding')
  else
    Result := LandrixXmlXPathStringItem(Text);
end;

{ format-number(value, picture[, name]): the value as a function argument
  of type xs:numeric? (an untyped value or node as xs:double, the empty
  sequence as NaN), the decimal format by name (XTDE1280) }
function TRun.FormatNumber(const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  Value, Picture, Name: TLandrixXmlUtf8;
  It: TLandrixXmlXPathItem;
  K, Scale: Integer;
  Scaled: Boolean;
begin
  Picture := FEvaluator.ItemString(FEvaluator.ConvertSequence(Args[1], FStringType, 'format-number()').Items[0]);
  Name := '';
  if High(Args) >= 2 then
    Name := LandrixXmlStringToUtf8(Trim(LandrixXmlUtf8ToString(FEvaluator.ItemString(
      FEvaluator.ConvertSequence(Args[2], FStringType, 'format-number()').Items[0]))));
  K := FC.DecimalFormats.IndexOf(LandrixXmlUtf8ToString(Name));
  if K < 0 then
    raise ELandrixXmlXPathError.CreateXPath('FODF1280', 'format-number(): there is no decimal format ' +
      LandrixXmlUtf8ToString(Name));
  if Args[0].Count = 0 then
    Value := 'NaN'
  else
  begin
    if Args[0].Count > 1 then
      raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'format-number(): the value must be one number');
    It := Args[0].Items[0];
    case It.Kind of
      xikInteger, xikDecimal, xikDouble, xikNonPositiveInteger, xikNegativeInteger, xikLong, xikInt,
      xikShort, xikByte, xikNonNegativeInteger, xikUnsignedLong, xikUnsignedInt, xikUnsignedShort,
      xikUnsignedByte, xikPositiveInteger:
        Value := FEvaluator.ItemString(It);
      xikFloat, xikUntypedAtomic, xikNode:
        { a float widened to xs:double, an untyped value cast }
        begin
          It := FEvaluator.EvaluateInFocus(FDoubleExpr, ItemFocus(It, 1, 1)).Items[0];
          Value := FEvaluator.ItemString(It);
        end;
    else
      raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'format-number(): the value must be a number');
    end;
  end;
  { a double in a picture with percent or per mille: multiplied as a double
    (Saxon: 0.545 is 55%) }
  Scaled := False;
  if (Args[0].Count > 0) and (It.Kind = xikDouble) then
  begin
    Scale := XPathPictureScale(Picture, TXPathDecimalFormat(FC.DecimalFormats.Objects[K]),
      (Value <> '') and (Value[1] = '-'));
    if Scale > 1 then
    begin
      if Scale = 100 then
        Value := FEvaluator.ItemString(FEvaluator.EvaluateInFocus(FTimes100Expr, ItemFocus(It, 1, 1)).Items[0])
      else
        Value := FEvaluator.ItemString(FEvaluator.EvaluateInFocus(FTimes1000Expr, ItemFocus(It, 1, 1)).Items[0]);
      Scaled := True;
    end;
  end;
  Result := LandrixXmlXPathStringItem(XPathFormatNumber(Value, Picture,
    TXPathDecimalFormat(FC.DecimalFormats.Objects[K]), Scaled));
end;

{ The value an atomic item (or a node: its string value) is compared by
  in grouping and key(): strings and untyped values as strings, numbers
  as xs:double (NaN equal to NaN; grouping tells integers and decimals
  apart by ExactNumber), durations of all three types alike, other types
  by their type and value. }
function TRun.AtomKey(const It: TLandrixXmlXPathItem): TLandrixXmlUtf8;
begin
  case It.Kind of
    xikNode, xikUntypedAtomic, xikString, xikAnyUri, xikNormalizedString, xikToken, xikLanguage, xikNMTOKEN,
    xikName, xikNCName, xikID, xikIDREF, xikENTITY:
      Result := 's' + FEvaluator.ItemString(It);
    xikInteger, xikDecimal, xikDouble, xikFloat, xikNonPositiveInteger, xikNegativeInteger, xikLong, xikInt,
    xikShort, xikByte, xikNonNegativeInteger, xikUnsignedLong, xikUnsignedInt, xikUnsignedShort,
    xikUnsignedByte, xikPositiveInteger:
      begin
        Result := 'n' + FEvaluator.ItemString(FEvaluator.EvaluateInFocus(FNumberExpr, ItemFocus(It, 1, 1)).Items[0]);
        if Result = 'n-0' then
          Result := 'n0';
      end;
    xikDuration, xikYearMonthDuration, xikDayTimeDuration:
      begin
        { equal across the types (P12M and P1Y, PT24H and P1D, the zero
          durations) }
        Result := 'u' + FEvaluator.ItemString(It);
        if Result = 'uP0M' then
          Result := 'uPT0S';
      end;
    xikBoolean:
      Result := 'b' + FEvaluator.ItemString(It);
    xikQName, xikDateTime, xikTime:
      Result := 'o' + LandrixXmlStringToUtf8(IntToStr(Ord(It.Kind))) + ':' +
        FEvaluator.ItemString(FEvaluator.EvaluateInFocus(FKeyNormExpr, ItemFocus(It, 1, 1)).Items[0]);
  else
    Result := 'o' + LandrixXmlStringToUtf8(IntToStr(Ord(It.Kind))) + ':' + FEvaluator.ItemString(It);
  end;
end;

{ Grouping as Saxon: items with the same AtomKey are compared with eq
  against the key that made the group, so two integers or decimals are
  equal only when they are (an xs:double or xs:float, '' here, is equal
  to each of the same double); the canonical value of an integer or
  decimal, else '' }
function TRun.ExactNumber(const It: TLandrixXmlXPathItem): TLandrixXmlUtf8;
begin
  case It.Kind of
    xikInteger, xikDecimal, xikNonPositiveInteger, xikNegativeInteger, xikLong, xikInt, xikShort, xikByte,
    xikNonNegativeInteger, xikUnsignedLong, xikUnsignedInt, xikUnsignedShort, xikUnsignedByte,
    xikPositiveInteger:
      Result := FEvaluator.ItemString(It);
  else
    Result := '';
  end;
end;

{ An id as Saxon makes them: "d", the number of the tree, then a letter
  for the kind (e element, t text, c comment, p processing instruction)
  and the number of the node among the nodes that are no attributes; an
  attribute: its element's id, "a" and its position. }
function TRun.GenerateId(Node: Integer): TLandrixXmlUtf8;
var
  T: TLandrixXmlXPathTree;
  B, I, J, K, N, Owner: Integer;
begin
  T := FEvaluator.TreeOfNode(Node, B);
  N := FEvaluator.TreeNumber(Node);
  Result := 'd' + LandrixXmlStringToUtf8(IntToStr(N + 1));
  I := Node - B;
  Owner := I;
  if T.Kind[I] = xnkAttribute then
    Owner := T.Parent[I];
  { a parentless attribute is the only node of its tree, as a document }
  if (Owner < 0) or (T.Kind[Owner] = xnkDocument) then
    Exit;
  { the numbers of the nodes that are no attributes, counted once per tree }
  if N >= Length(FIdTrees) then
  begin
    SetLength(FIdTrees, 2 * N + 8);
    SetLength(FIdNumbers, 2 * N + 8);
  end;
  if (FIdTrees[N] <> T) or (Length(FIdNumbers[N]) <> T.Count) then
  begin
    FIdTrees[N] := T;
    SetLength(FIdNumbers[N], T.Count);
    K := 0;
    if T.Kind[0] <> xnkDocument then
      K := 1;
    for J := 0 to T.Count - 1 do
    begin
      FIdNumbers[N][J] := K;
      if T.Kind[J] <> xnkAttribute then
        Inc(K);
    end;
  end;
  K := FIdNumbers[N][Owner];
  case T.Kind[Owner] of
    xnkElement: Result := Result + 'e';
    xnkText: Result := Result + 't';
    xnkComment: Result := Result + 'c';
  else
    Result := Result + 'p';
  end;
  Result := Result + LandrixXmlStringToUtf8(IntToStr(K));
  if Owner <> I then
    Result := Result + 'a' + LandrixXmlStringToUtf8(IntToStr(I - Owner));
end;

{ The index of key K in the tree whose root is Root, built on first use:
  every node that matches a declaration's pattern under each value of its
  use expression. }
function TRun.KeyIndex(K: TXsltKey; Root: Integer): TObject;
var
  Index: TKeyIndex;
  T: TLandrixXmlXPathTree;
  B, I, J, D, P: Integer;
  Decl: TXsltKeyDecl;
  V: TLandrixXmlXPathSequence;
  Value: string;
  Nodes: TKeyNodes;
  SavedNode: Integer;
  SavedCurrent: TLandrixXmlXPathSequence;
  Matched, SavedRegex, SavedGroupActive, Strings: Boolean;
  SavedRule: TXsltRule;
begin
  Strings := KeyStrings(K);
  for I := 0 to Integer(FKeyIndexes.Count) - 1 do
  begin
    Index := TKeyIndex(FKeyIndexes[I]);
    if (Index.Key = K) and (Index.Root = Root) then
    begin
      if Index.Building then
        raise ELandrixXmlXPathError.CreateXPath('XTDE0640', 'the key ' + LandrixXmlUtf8ToString(K.Name) +
          ' is used to build itself');
      Result := Index;
      Exit;
    end;
  end;
  Index := TKeyIndex.Create;
  FKeyIndexes.Add(Index);
  Index.Key := K;
  Index.Root := Root;
  Index.Building := True;
  Result := Index;
  T := FEvaluator.TreeOfNode(Root, B);
  SavedNode := FEvaluator.CurrentNode;
  SavedCurrent := FCurrent;
  { the use expressions see no captured substrings of xsl:analyze-string }
  SavedRegex := FRegexActive;
  FRegexActive := False;
  SavedRule := FRule;
  FRule := nil;
  { and no current group (XTDE1061): the index does not depend on its
    first caller }
  SavedGroupActive := FGroupActive;
  FGroupActive := False;
  try
    for I := 0 to T.Count - 1 do
      for D := 0 to Integer(K.Decls.Count) - 1 do
      begin
        Decl := TXsltKeyDecl(K.Decls[D]);
        { current() in the pattern and the use expression is the node }
        FEvaluator.CurrentNode := I + B;
        FCurrent := LandrixXmlXPathEmpty;
        Matched := False;
        for P := 0 to Integer(Length(Decl.Patterns)) - 1 do
          if PatternMatches(Decl.Patterns[P], I + B, Decl.Relative[P]) then
          begin
            Matched := True;
            Break;
          end;
        if not Matched then
          Continue;
        if Decl.Use <> nil then
          V := FEvaluator.EvaluateInFocus(Decl.Use, NodeFocus(I + B, 1, 1))
        else
        begin
          { the sequence constructor, in a frame of its own }
          FEvaluator.PushFrame(Decl.FrameSize);
          try
            V := TemporarySequence(Decl.Body, NodeFocus(I + B, 1, 1), FC.FindMode(''));
          finally
            FEvaluator.PopFrame;
          end;
        end;
        for J := 0 to Integer(V.Count) - 1 do
        begin
          { a declaration of the key in backwards compatible mode: all
            values as strings }
          if Strings then
            Value := 's' + LandrixXmlUtf8ToKey(FEvaluator.ItemString(V.Items[J]))
          else
            Value := LandrixXmlUtf8ToKey(AtomKey(V.Items[J]));
          { NaN is equal to no value }
          if Value = 'nNaN' then
            Continue;
          P := Index.Map.IndexOf(Value);
          if P >= 0 then
            Nodes := TKeyNodes(Index.Map.Objects[P])
          else
          begin
            Nodes := TKeyNodes.Create;
            Index.Map.AddObject(Value, Nodes);
          end;
          Nodes.Add(I + B);
        end;
      end;
    Index.Building := False;
  except
    { not kept half built }
    FKeyIndexes.Delete(Integer(FKeyIndexes.IndexOf(Index)));
    FEvaluator.CurrentNode := SavedNode;
    FCurrent := SavedCurrent;
    FRegexActive := SavedRegex;
    FRule := SavedRule;
    FGroupActive := SavedGroupActive;
    raise;
  end;
  FEvaluator.CurrentNode := SavedNode;
  FCurrent := SavedCurrent;
  FRegexActive := SavedRegex;
  FRule := SavedRule;
  FGroupActive := SavedGroupActive;
end;

function TRun.KeyStrings(K: TXsltKey): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to Integer(K.Decls.Count) - 1 do
    if TXsltKeyDecl(K.Decls[I]).Backwards then
      Result := True;
end;

{ key(name, values[, top]): the nodes of the tree of top (the context
  node) that have one of the values under the key, inside top, in
  document order }
function TRun.KeyFunction(const Args: array of TLandrixXmlXPathSequence;
  const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
var
  Name, Uri, Local: TLandrixXmlUtf8;
  I, J, Top, Root, B, N, X: Integer;
  K: TXsltKey;
  Strings: Boolean;
  Index: TKeyIndex;
  T: TLandrixXmlXPathTree;
  Found: array of Integer;
  Count: Integer;
  Nodes: TKeyNodes;
  Inside: Boolean;
begin
  Result := LandrixXmlXPathEmpty;
  Found := nil;
  if (Args[0].Count <> 1) then
    raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'key(): the name must be one string');
  { a lexical QName, its prefix bound by the calling expression }
  XsltNameArgument(FEvaluator, Args[0], 'XTDE1260', 'key()', '', Uri, Local);
  Name := XsltClarkOf(Uri, Local);
  I := FC.Keys.IndexOf(LandrixXmlUtf8ToString(Name));
  if I < 0 then
    raise ELandrixXmlXPathError.CreateXPath('XTDE1260', 'key(): there is no key ' + LandrixXmlUtf8ToString(Name));
  K := TXsltKey(FC.Keys.Objects[I]);
  Strings := KeyStrings(K);
  if High(Args) >= 2 then
  begin
    if (Args[2].Count <> 1) or (Args[2].Items[0].Kind <> xikNode) then
      raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'key(): the third argument must be one node');
    Top := Args[2].Items[0].Node;
  end
  else
  begin
    if Focus.Node < 0 then
      raise ELandrixXmlXPathError.CreateXPath('XTDE1270', 'key(): the context item is no node');
    Top := Focus.Node;
  end;
  T := FEvaluator.TreeOfNode(Top, B);
  Root := Top - B;
  while T.Parent[Root] >= 0 do
    Root := T.Parent[Root];
  { two arguments: the whole document of the context node }
  if High(Args) < 2 then
    Top := Root + B;
  if T.Kind[Root] <> xnkDocument then
    raise ELandrixXmlXPathError.CreateXPath('XTDE1270', 'key(): the node is not in a document');
  Index := TKeyIndex(KeyIndex(K, Root + B));
  Count := 0;
  for I := 0 to Integer(Args[1].Count) - 1 do
  begin
    if Strings then
      J := Index.Map.IndexOf('s' + LandrixXmlUtf8ToKey(FEvaluator.ItemString(Args[1].Items[I])))
    else
      J := Index.Map.IndexOf(LandrixXmlUtf8ToKey(AtomKey(Args[1].Items[I])));
    if J < 0 then
      Continue;
    Nodes := TKeyNodes(Index.Map.Objects[J]);
    for N := 0 to Nodes.Count - 1 do
    begin
      { inside Top (its descendants or itself) }
      X := Nodes.Nodes[N] - B;
      Inside := Top = Root + B;
      while not Inside and (X >= 0) do
      begin
        Inside := X + B = Top;
        X := T.Parent[X];
      end;
      if not Inside then
        Continue;
      if Count = Length(Found) then
        SetLength(Found, 2 * Count + 8);
      Found[Count] := Nodes.Nodes[N];
      Inc(Count);
    end;
  end;
  { document order, each node once }
  Count := SortUniqueIntegers(Found, Count);
  for I := 0 to Count - 1 do
    LandrixXmlXPathAppend(Result, LandrixXmlXPathNodeItem(Found[I]).Items[0]);
end;

{ xsl:for-each-group: the groups in the order of their first item, the
  body once per group with its first item as context item }
procedure TRun.DoForEachGroup(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  R: TReceiver);
var
  Population, Keys, Firsts: TLandrixXmlXPathSequence;
  Groups, GroupKeys: TSequenceArray;
  Order, LastItem: TSortOrder;
  GroupExact: TLandrixXmlUtf8Array;
  Map: TXsltStringList;
  I, J, G, P, Count: Integer;
  Key, Previous, Exact: TLandrixXmlUtf8;
  Starts, Matched: Boolean;
  SavedGroup, SavedKey: TLandrixXmlXPathSequence;
  SavedActive, SavedHasKey: Boolean;
  SavedLazy: Integer;

  { an atomic key: a node as its string value }
  function Atomic(const It: TLandrixXmlXPathItem): TLandrixXmlXPathItem;
  begin
    Result := It;
    if It.Kind = xikNode then
    begin
      Result.Kind := xikUntypedAtomic;
      Result.Text := FEvaluator.ItemString(It);
      Result.Node := -1;
      Result.Bits := 0;
      Result.Payload := nil;
    end;
  end;

  { the group remembered under K (the first), -1 if none }
  function GroupOf(const K: TLandrixXmlUtf8): Integer;
  var
    X: Integer;
  begin
    Result := -1;
    if Map.Find(LandrixXmlUtf8ToKey(K), X) then
      Result := TKeyNodes(Map.Objects[X]).Nodes[0];
  end;

  { group G under K unless one is there (in a TKeyNodes, freed with the
    map) }
  procedure Remember(const K: TLandrixXmlUtf8; G: Integer);
  var
    Box: TKeyNodes;
  begin
    if GroupOf(K) >= 0 then
      Exit;
    Box := TKeyNodes.Create;
    Box.Add(G);
    Map.AddObject(LandrixXmlUtf8ToKey(K), Box);
  end;

  { whether a key with the exact number E is equal to group G's }
  function SameNumber(G: Integer; const E: TLandrixXmlUtf8): Boolean;
  begin
    Result := (E = '') or (GroupExact[G] = '') or (GroupExact[G] = E);
  end;

  procedure NewGroup(const It: TLandrixXmlXPathItem; const K: TLandrixXmlXPathSequence);
  begin
    SetLength(Groups, Count + 1);
    SetLength(GroupKeys, Count + 1);
    SetLength(GroupExact, Count + 1);
    SetLength(LastItem, Count + 1);
    GroupExact[Count] := '';
    LastItem[Count] := -1;
    Groups[Count] := LandrixXmlXPathEmpty;
    LandrixXmlXPathAppend(Groups[Count], It);
    GroupKeys[Count] := K;
    Inc(Count);
  end;

begin
  Groups := nil;
  GroupKeys := nil;
  GroupExact := nil;
  LastItem := nil;
  Count := 0;
  { a computed unknown collation: FOCH0002 as Saxon (XTDE1110 in the
    specification; Saxon raises that for a literal one) }
  if Instr.CollationAvt <> nil then
    CheckCollation(Instr, Trim8(EvalAvt(Instr, Instr.CollationAvt, Focus)), 'FOCH0002');
  Population := Eval(Instr, Instr.Select, Focus);
  Map := TXsltStringList.Create;
  try
    Map.CaseSensitive := True;
    Map.Sorted := True;
    Previous := '';
    for I := 0 to Integer(Population.Count) - 1 do
      case Instr.GroupKind of
        0:
          begin
            Keys := Eval(Instr, Instr.Test, ItemFocus(Population.Items[I], I + 1, Population.Count));
            for J := 0 to Integer(Keys.Count) - 1 do
            begin
              Key := AtomKey(Keys.Items[J]);
              Exact := ExactNumber(Keys.Items[J]);
              { the first group whose key is equal: any of the same key
                for a double (or a value that is no number), else one
                of the same exact number or one a double made }
              if Exact = '' then
                G := GroupOf('1' + Key)
              else
              begin
                G := GroupOf('3' + Exact);
                P := GroupOf('2' + Key);
                if (P >= 0) and ((G < 0) or (P < G)) then
                  G := P;
              end;
              if G >= 0 then
              begin
                { an item in a group once, even with two equal keys }
                if LastItem[G] <> I then
                  LandrixXmlXPathAppend(Groups[G], Population.Items[I]);
              end
              else
              begin
                NewGroup(Population.Items[I], LandrixXmlXPathEmpty);
                G := Count - 1;
                GroupExact[G] := Exact;
                LandrixXmlXPathAppend(GroupKeys[G], Atomic(Keys.Items[J]));
                Remember('1' + Key, G);
                { the doubles of a number key, for the exact ones }
                if Exact <> '' then
                  Remember('3' + Exact, G)
                else if Key[1] = 'n' then
                  Remember('2' + Key, G);
              end;
              LastItem[G] := I;
            end;
          end;
        1:
          begin
            Keys := Eval(Instr, Instr.Test, ItemFocus(Population.Items[I], I + 1, Population.Count));
            if Keys.Count <> 1 then
              Fail(Instr, 'XTTE1100', 'xsl:for-each-group: group-adjacent must give one value');
            Key := AtomKey(Keys.Items[0]);
            Exact := ExactNumber(Keys.Items[0]);
            if (Count > 0) and (Key = Previous) and SameNumber(Count - 1, Exact) then
              LandrixXmlXPathAppend(Groups[Count - 1], Population.Items[I])
            else
            begin
              NewGroup(Population.Items[I], LandrixXmlXPathEmpty);
              GroupExact[Count - 1] := Exact;
              LandrixXmlXPathAppend(GroupKeys[Count - 1], Atomic(Keys.Items[0]));
            end;
            Previous := Key;
          end;
      else
        begin
          if Population.Items[I].Kind <> xikNode then
            Fail(Instr, 'XTTE1120', 'xsl:for-each-group: a pattern needs nodes to group');
          FEvaluator.CurrentNode := Population.Items[I].Node;
          FCurrent := LandrixXmlXPathEmpty;
          Matched := False;
          for P := 0 to Integer(Length(Instr.CountPatterns)) - 1 do
            if PatternMatches(Instr.CountPatterns[P], Population.Items[I].Node, Instr.CountRelative[P]) then
            begin
              Matched := True;
              Break;
            end;
          if Instr.GroupKind = 2 then
            Starts := (Count = 0) or Matched
          else
            Starts := (Count = 0) or (Previous = 'end');
          if Starts then
            NewGroup(Population.Items[I], LandrixXmlXPathEmpty)
          else
            LandrixXmlXPathAppend(Groups[Count - 1], Population.Items[I]);
          if Matched then
            Previous := 'end'
          else
            Previous := '';
        end;
      end;
  finally
    for G := 0 to Integer(Map.Count) - 1 do
      Map.Objects[G].Free;
    Map.Free;
  end;
  SavedGroup := FGroup;
  SavedKey := FGroupKey;
  SavedActive := FGroupActive;
  SavedLazy := FGroupLazyDepth;
  SavedHasKey := FGroupHasKey;
  Order := nil;
  SetLength(Order, Count);
  for G := 0 to Count - 1 do
    Order[G] := G;
  if Instr.SortKeys <> nil then
  begin
    { the groups in the order of their sort keys }
    Firsts := LandrixXmlXPathEmpty;
    for G := 0 to Count - 1 do
      LandrixXmlXPathAppend(Firsts, Groups[G].Items[0]);
    Order := SortOrder(Instr, Focus, Mode, Firsts, Groups, GroupKeys, Instr.GroupKind <= 1);
  end;
  try
    for J := 0 to Count - 1 do
    begin
      G := Order[J];
      FGroup := Groups[G];
      FGroupKey := GroupKeys[G];
      FGroupActive := True;
      FGroupHasKey := Instr.GroupKind <= 1;
      FGroupLazyDepth := FEvaluator.LazyDepth;
      Exec(Instr.Body, ItemFocus(Groups[G].Items[0], J + 1, Count), Mode, R);
    end;
  finally
    FGroup := SavedGroup;
    FGroupKey := SavedKey;
    FGroupActive := SavedActive;
    FGroupLazyDepth := SavedLazy;
    FGroupHasKey := SavedHasKey;
  end;
end;

procedure TRun.ExecCore(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  SavedRule: TXsltRule;
begin
  case Instr.Kind of
    xskText:
      DoText(Instr, Focus, R);
    xskLiteralElement:
      LiteralElement(Instr, Focus, Mode, R);
    xskValueOf:
      DoValueOf(Instr, Focus, Mode, R);
    xskVariable:
      DoVariable(Instr, Focus, Mode);
    xskIf:
      if Test(Instr, Focus) then
        Exec(Instr.Body, Focus, Mode, R);
    xskChoose:
      Exec(ChosenBody(Instr, Focus), Focus, Mode, R);
    xskForEach:
      begin
        SavedRule := FRule;
        FRule := nil;
        try
          DoForEach(Instr, Focus, Mode, R);
        finally
          FRule := SavedRule;
        end;
      end;
    xskSequence, xskCopyOf:
      DoSequence(Instr, Focus, R);
    xskCopy:
      CopyInstr(Instr, Focus, Mode, R);
    xskElement:
      DoElement(Instr, Focus, Mode, R);
    xskAttribute:
      DoAttribute(Instr, Focus, Mode, R);
    xskComment:
      R.Comment(CommentText(InstrText(Instr, Focus, Mode)));
    xskProcessingInstruction:
      DoProcessingInstruction(Instr, Focus, Mode, R);
    xskMessage:
      DoMessage(Instr, Focus, Mode);
    xskDocument:
      DoDocument(Instr, Focus, Mode, R);
    xskApplyTemplates:
      DoApplyTemplates(Instr, Focus, Mode, R);
    xskCallTemplate:
      DoCallTemplate(Instr, Focus, Mode, R);
    xskNumber:
      DoNumber(Instr, Focus, R);
    xskForEachGroup, xskAnalyzeString:
      begin
        SavedRule := FRule;
        FRule := nil;
        try
          if Instr.Kind = xskForEachGroup then
            DoForEachGroup(Instr, Focus, Mode, R)
          else
            DoAnalyzeString(Instr, Focus, Mode, R);
        finally
          FRule := SavedRule;
        end;
      end;
    xskPerformSort:
      DoPerformSort(Instr, Focus, Mode, R);
    xskNextMatch, xskApplyImports:
      DoNextMatch(Instr, Focus, Mode, R);
    xskResultDocument:
      DoResultDocument(Instr, Focus, Mode);
    xskUseAttributeSets:
      DoUseAttributeSets(Instr, Focus, Mode, R);
    xskNamespace:
      DoNamespace(Instr, Focus, Mode, R);
    xskExtension:
      if Instr.HasFallback then
        Exec(Instr.Body, Focus, Mode, R)
      else
        Fail(Instr, 'XTDE1450', 'unknown extension instruction <' + LandrixXmlUtf8ToString(Instr.Text) + '>');
  else
    { xsl:when is not compiled as an instruction of its own }
  end;
end;

procedure TRun.BindGlobals;
var
  I, J: Integer;
  G: TXsltGlobal;
  Found: Boolean;
  V: TLandrixXmlXPathSequence;
  It: TLandrixXmlXPathItem;
  X: TLandrixXmlXPathExpression;
  Ctx: TLandrixXmlXPathStaticContext;
  Root, K, AddedCount: Integer;
  Added: array of TLandrixXmlXPathTree;
  AddedNodes: array of Integer;
begin
  Added := nil;
  AddedNodes := nil;
  AddedCount := 0;
  FEvaluator.SetGlobalCount(FC.GlobalCount);
  { the context item of the globals: the source's document node, none
    without a source (a use of the context is XPDY0002) }
  Root := 0;
  if FEmpty <> nil then
    Root := -1;
  for I := 0 to Integer(FC.Globals.Count) - 1 do
  begin
    G := TXsltGlobal(FC.Globals[I]);
    Found := False;
    if G.IsParam then
      for J := 0 to Integer(Length(FSettings.ParamNames)) - 1 do
        if FSettings.ParamNames[J] = G.Name then
        begin
          Found := True;
          case FSettings.ParamKinds[J] of
            0:
              begin
                It.Kind := xikUntypedAtomic;
                It.Node := -1;
                It.Bits := 0;
                It.Text := FSettings.ParamValues[J];
                It.Payload := nil;
                V := LandrixXmlXPathEmpty;
                LandrixXmlXPathAppend(V, It);
              end;
            1:
              if (FSettings.ParamTrees[J] = FSource) or (FSettings.ParamTrees[J] = FGivenSource) then
                V := LandrixXmlXPathNodeItem(0)
              else
              begin
                { one tree given for two parameters: the same nodes }
                K := 0;
                while (K < AddedCount) and (Added[K] <> FSettings.ParamTrees[J]) do
                  Inc(K);
                if K = AddedCount then
                begin
                  if AddedCount = Length(Added) then
                  begin
                    SetLength(Added, 2 * AddedCount + 4);
                    SetLength(AddedNodes, 2 * AddedCount + 4);
                  end;
                  Added[K] := FSettings.ParamTrees[J];
                  AddedNodes[K] := FEvaluator.AddTree(FSettings.ParamTrees[J]);
                  Inc(AddedCount);
                end;
                V := LandrixXmlXPathNodeItem(AddedNodes[K]);
              end;
          else
            begin
              Ctx := TLandrixXmlXPathStaticContext.Create;
              try
                Ctx.Profile := xppSaxon;
                X := TLandrixXmlXPathExpression.Create(FSettings.ParamValues[J], Ctx);
              finally
                Ctx.Free;
              end;
              FParamExprs.Add(X);
              V := FEvaluator.EvaluateInFocus(X, NoFocus);
            end;
          end;
          if G.HasAs then
            try
              V := FEvaluator.ConvertSequence(V, G.AsType, '$' + LandrixXmlUtf8ToString(G.Name));
            except
              on E: ELandrixXmlXPathError do
                raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTTE0590',
                  System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), G.Module, G.Line, G.Column);
            end;
          FEvaluator.BindValue(G.Slot, V);
        end;
    if Found then
      Continue;
    if G.Required then
      raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTDE0050', 'the required parameter ' +
        LandrixXmlUtf8ToString(G.Name) + ' is not supplied', G.Module, G.Line, G.Column);
    if G.Select <> nil then
    begin
      if G.HasAs then
        FEvaluator.BindLazyAs(G.Slot, G.Select, Root, G.AsType)
      else
        FEvaluator.BindLazy(G.Slot, G.Select, Root);
    end
    else if G.Call <> nil then
      FEvaluator.BindLazy(G.Slot, G.Call, Root)
    else if G.HasAs then
      FEvaluator.BindValue(G.Slot, FEvaluator.ConvertSequence(LandrixXmlXPathEmpty, G.AsType,
        '$' + LandrixXmlUtf8ToString(G.Name)))
    else
      FEvaluator.BindValue(G.Slot, LandrixXmlXPathStringItem(''));
  end;
end;

procedure TRun.Start(Target: TLandrixXmlXPathTree);
var
  R: TTreeReceiver;
  T2: TLandrixXmlXPathTree;
  Mode: TXsltMode;
  T: TXsltTemplate;
  I: Integer;
  Params: TSuppliedArray;
  Written: Boolean;
begin
  FStackBase := @R;
  BindGlobals;
  Params := nil;
  Target.BeginBuild(True);
  R := TTreeReceiver.Create(Self, Target, True);
  R.FRawProps := TXsltOutputProperties(FSettings.PrincipalRaw);
  FImplicit := Target;
  FImplicitReceiver := R;
  try
    if FSettings.InitialTemplate <> '' then
    begin
      if not FC.NamedTemplates.Find(LandrixXmlUtf8ToString(FSettings.InitialTemplate), I) then
        Fail(nil, 'XTDE0040', 'no template named ' + LandrixXmlUtf8ToString(FSettings.InitialTemplate));
      T := TXsltTemplate(FC.NamedTemplates.Objects[I]);
      { XSLT 2.0: the initial template has no required parameter }
      for I := 0 to Integer(T.Params.Count) - 1 do
        if TXsltInstr(T.Params[I]).Required then
          Fail(TXsltInstr(T.Params[I]), 'XTDE0060', 'the initial template has the required parameter ' +
            LandrixXmlUtf8ToString(TXsltInstr(T.Params[I]).VarName));
      Mode := FC.FindMode(FSettings.InitialMode);
      if Mode = nil then
        Mode := FC.FindMode('');
      if FEmpty = nil then
        Invoke(T, NodeFocus(0, 1, 1), Mode, Params, R)
      else
        Invoke(T, NoFocus, Mode, Params, R);
    end
    else
    begin
      if FEmpty <> nil then
        Fail(nil, 'XTDE0040', 'neither a source document nor an initial template');
      Mode := FC.FindMode(FSettings.InitialMode);
      if Mode = nil then
        Fail(nil, 'XTDE0045', 'the stylesheet has no mode ' + LandrixXmlUtf8ToString(FSettings.InitialMode));
      ApplyTemplates(nil, LandrixXmlXPathNodeItem(0), Mode, Params, R);
    end;
    R.Finish;
    Written := R.FWritten;
  finally
    FImplicitReceiver := nil;
    R.Free;
  end;
  { an xsl:result-document made the principal result: it is the result
    (an implicit one besides it is XTDE1490, also an empty string) }
  if FPrincipal <> nil then
  begin
    if (Target.Count > 1) or Written then
      Fail(nil, 'XTDE1490', 'the principal result is written by xsl:result-document and by the templates');
    T2 := FPrincipal;
    FPrincipal := nil;
    I := AddTree(T2);
    Target.BeginBuild(True);
    R := TTreeReceiver.Create(Self, Target, True);
    try
      CopyNode(I, R);
      R.Finish;
    finally
      R.Free;
    end;
    Target.BaseUri := T2.BaseUri;
    FSettings.PrincipalProperties := FPrincipalProps;
    FPrincipalProps := nil;
  end
  else
    { the implicit result is one with an empty href: the base output URI }
    Target.BaseUri := FSettings.BaseOutputUri;
  { the run succeeded: the secondary results go to the transformer }
  FResults.OwnsObjects := False;
  for I := 0 to Integer(FResults.Count) - 1 do
    FSettings.ResultDocuments.Add(FResults[I]);
  FResults.Clear;
  FResults.OwnsObjects := True;
end;

procedure XsltRun(Compiled: TObject; Settings: TXsltRunSettings; Source, Target: TLandrixXmlXPathTree);
var
  Run: TRun;
begin
  Run := TRun.Create(TXsltCompiled(Compiled), Settings, Source);
  try
    Run.Start(Target);
  finally
    Run.Free;
  end;
end;

end.
