<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- an error after a left out element: its position still counts (line 5) -->
<xsl:template name="x" use-when="false()">
</xsl:template>
<xsl:template match="/"><r><xsl:value-of select="1 +"/></r></xsl:template>
</xsl:stylesheet>
