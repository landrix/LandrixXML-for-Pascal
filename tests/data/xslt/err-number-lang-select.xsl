<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a bad lang is reported before a select without a node -->
<xsl:template match="/"><r><xsl:number select="/*/none" lang="#####"/></r></xsl:template>
</xsl:stylesheet>
