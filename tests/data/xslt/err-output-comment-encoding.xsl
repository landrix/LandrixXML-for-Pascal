<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- in a comment no character reference is possible -->
<xsl:output encoding="us-ascii"/>
<xsl:template match="/"><r><xsl:comment>&#xE9;</xsl:comment></r></xsl:template>
</xsl:stylesheet>
