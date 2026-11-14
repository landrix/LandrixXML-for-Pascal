<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- use-when has no context item -->
<xsl:template match="/" use-when="exists(.)"><r/></xsl:template>
</xsl:stylesheet>
