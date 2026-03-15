package main

deny[msg] {
    input[i].Cmd == "from"
    val := input[i].Value[0]
    contains(val, ":latest")
    msg := "Dockerfile must not use :latest tag — pin a specific version"
}

deny[msg] {
    not has_user
    msg := "Dockerfile must include a USER instruction — do not run as root"
}

deny[msg] {
    input[i].Cmd == "run"
    val := concat(" ", input[i].Value)
    contains(val, "curl")
    contains(val, "|")
    contains(val, "sh")
    msg := "Do not pipe curl output to shell — download and verify first"
}

deny[msg] {
    input[i].Cmd == "expose"
    val := input[i].Value[0]
    to_number(val) < 1024
    val != "443"
    val != "80"
    msg := sprintf("Avoid exposing privileged port %s — use a port >= 1024", [val])
}

deny[msg] {
    input[i].Cmd == "env"
    val := concat(" ", input[i].Value)
    contains(lower(val), "password")
    msg := "Do not set passwords via ENV — use secrets management"
}

deny[msg] {
    input[i].Cmd == "env"
    val := concat(" ", input[i].Value)
    contains(lower(val), "secret")
    msg := "Do not set secrets via ENV — use secrets management"
}

warn[msg] {
    not has_healthcheck
    msg := "Consider adding a HEALTHCHECK instruction"
}

has_user {
    input[i].Cmd == "user"
}

has_healthcheck {
    input[i].Cmd == "healthcheck"
}
