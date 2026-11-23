<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- default-mode on xsl:output and xsl:decimal-format; xsl:default-mode in a
     user-defined data element is not checked -->
<xsl:output default-mode="m:o"/>
<xsl:decimal-format name="f" default-mode="m:o"/>
<m:data xsl:default-mode="undeclared:no"/>
<xsl:template match="/"><r><xsl:apply-templates select="doc"/></r></xsl:template>
</xsl:stylesheet>
