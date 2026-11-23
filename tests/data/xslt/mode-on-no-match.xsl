<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- xsl:mode on-no-match: the six sets of built-in template rules, with
     parameters passed on -->
<xsl:mode name="m:text" on-no-match=" text-only-copy "/>
<xsl:mode name="m:deep-copy" on-no-match="deep-copy"/>
<xsl:mode name="m:shallow-copy" on-no-match="shallow-copy"/>
<xsl:mode name="m:deep-skip" on-no-match="deep-skip"/>
<xsl:mode name="m:shallow-skip" on-no-match="shallow-skip"/>
<xsl:mode name="m:fail" on-no-match="fail"/>
<xsl:template match="/">
  <r>
    <text><xsl:apply-templates select="/" mode="m:text"><xsl:with-param name="q" select="'Q'"/></xsl:apply-templates></text>
    <deep-copy><xsl:apply-templates select="/" mode="m:deep-copy"/></deep-copy>
    <shallow-copy><xsl:apply-templates select="/" mode="m:shallow-copy"><xsl:with-param name="q" select="'Q'"/></xsl:apply-templates></shallow-copy>
    <shallow-copy-attr><xsl:apply-templates select="//@*" mode="m:shallow-copy"/></shallow-copy-attr>
    <deep-skip><xsl:apply-templates select="/" mode="m:deep-skip"/>|<xsl:apply-templates select="/doc/x" mode="m:deep-skip"/>|<xsl:apply-templates select="//y" mode="m:deep-skip"/></deep-skip>
    <shallow-skip><xsl:apply-templates select="/" mode="m:shallow-skip"><xsl:with-param name="q" select="'Q'"/></xsl:apply-templates></shallow-skip>
    <fail><xsl:apply-templates select="//y" mode="m:fail"/></fail>
  </r>
</xsl:template>
<xsl:template match="y" mode="#all">
  <xsl:param name="q" select="'-'"/>
  <Y q="{$q}" pos="{position()}" last="{last()}"/>
</xsl:template>
<xsl:template match="@b" mode="m:shallow-skip">
  <xsl:param name="q" select="'-'"/>
  <B q="{$q}" pos="{position()}"/>
</xsl:template>
</xsl:stylesheet>
