<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- shallow-copy of the document node into a sequence: a document node of
     its own (raw text in it is escaped, as in Saxon); adjacent atomic
     values stay apart, also around an empty document node -->
<xsl:mode name="m:s" on-no-match="shallow-copy"/>
<xsl:template match="a" mode="m:s"><xsl:text disable-output-escaping="yes">&lt;hit/&gt;</xsl:text></xsl:template>
<xsl:mode name="m:t" on-no-match="shallow-copy"/>
<xsl:template match="doc" mode="m:t"><xsl:sequence select="2, 3"/></xsl:template>
<xsl:mode name="m:e" on-no-match="shallow-copy"/>
<xsl:template match="doc" mode="m:e"/>
<xsl:template match="/">
  <xsl:variable name="v" as="document-node()"><xsl:apply-templates select="/" mode="m:s"/></xsl:variable>
  <r><xsl:copy-of select="$v"/></r>
  <s><xsl:sequence select="1"/><xsl:apply-templates select="/" mode="m:t"/><xsl:sequence select="4"/></s>
  <e><xsl:sequence select="1"/><xsl:apply-templates select="/" mode="m:e"/><xsl:sequence select="4"/></e>
</xsl:template>
</xsl:stylesheet>
