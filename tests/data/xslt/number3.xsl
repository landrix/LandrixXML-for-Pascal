<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- roman numerals from 5000 on -->
<xsl:template match="/"><r><xsl:number value="5000" format="I"/>|<xsl:number value="6001" format="i"/></r></xsl:template>
</xsl:stylesheet>
