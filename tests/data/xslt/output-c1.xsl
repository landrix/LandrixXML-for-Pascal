<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- U+007F to U+009F and U+2028 are character references in UTF-8 as well -->
<xsl:template match="/"><r a="&#x7F;&#x80;&#x85;&#x9F;&#xA0;&#x2028;">&#x7F;&#x80;&#x85;&#x9F;&#xA0;&#x2028;&#x2029;</r></xsl:template>
</xsl:stylesheet>
