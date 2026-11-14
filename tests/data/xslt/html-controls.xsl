<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- C1 controls as lower case hex references, DEL left out (as Saxon);
     a content type meta with white space around its http-equiv -->
<xsl:output method="html" indent="no"/>
<xsl:template match="/"><html><head><meta http-equiv=" Content-Type " content="x"/></head><body><p a="&#x8A;&#127;&#xA0;">&#x8A;&#127;&#x9F;x</p></body></html></xsl:template>
</xsl:stylesheet>
