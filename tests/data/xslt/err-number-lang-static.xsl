<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a literal lang that is no language code -->
<xsl:template match="/"><r><xsl:number value="2" lang="#####"/></r></xsl:template>
</xsl:stylesheet>
