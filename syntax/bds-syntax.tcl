set title "bds-def"
set spec {
    stack
        {line /bds OCTAL-DIGIT , OCTAL-DIGIT {''} {TITLE} {''}}
        {line /date YYYY-MM-DD}
        {opt /preamble TEXT }
        {line /items {loop {line (newline) (indent) item-def (unindent)} {}}}
}