<?xml version="1.0" encoding="UTF-8"?>
<!-- cdata-section-elements with method xhtml (not indented inside); html
     ignores it (cdata-section-elements-html) -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:h="http://www.w3.org/1999/xhtml">
  <xsl:output method="xhtml" cdata-section-elements="h:p h:div example" indent="yes"/>
  <xsl:template match="/">
    <html xmlns="http://www.w3.org/1999/xhtml">
      <head><title>t</title></head>
      <body>
        <p>a&lt;b&#10;  c</p>
        <div><xsl:text>  </xsl:text><span>s</span>t <p>q</p>u</div>
        <example xmlns="">e</example>
        <pre>x</pre>
      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>
