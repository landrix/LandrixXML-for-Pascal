<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- a processing instruction with ">" in HTML -->
<xsl:output method="html"/>
<xsl:template match="/"><html><xsl:processing-instruction name="p">a > b</xsl:processing-instruction></html></xsl:template>
</xsl:stylesheet>
