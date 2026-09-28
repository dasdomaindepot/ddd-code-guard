#!/usr/bin/env bash
#
# Selbsttest für check-migrations.
#
# Da ein Git-Verlauf nötig ist, wird jeder Fall zur Laufzeit in einem
# mktemp-Verzeichnis aufgebaut: Basis-Commit auf `main`, Branch `feature`,
# danach die neue Migration als Commit oder unverändert im Arbeitsbaum. Das
# Script wird mit <projektverzeichnis> <basis-ref=main> aufgerufen und prüft
# Exit-Code und Ausgabe. Am Ende:
#   OK: alle Fälle bestanden   (Exit 0)
# sonst eine Meldung und Exit 1.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$HERE/../.." && pwd)"
SCRIPT="$BASE_DIR/claude/skills/code-quality/bin/check-migrations"

if [ ! -x "$SCRIPT" ]; then
    echo "FEHLER: Script nicht gefunden oder nicht ausführbar: $SCRIPT" >&2
    exit 1
fi

RC=0
OUT=""
fail=0

TMPDIRS=()
cleanup() {
    for d in "${TMPDIRS[@]:-}"; do
        [ -n "$d" ] && rm -rf "$d"
    done
}
trap cleanup EXIT

run_script() {
    if OUT="$("$SCRIPT" "$@" 2>&1)"; then
        RC=0
    else
        RC=$?
    fi
}

expect() {
    local exp_rc="$1"; shift
    case "$exp_rc" in
        ''|*[!0-9]*) echo "FEHLER: ${FUNCNAME[0]} ohne Exit-Code aufgerufen: $exp_rc" >&2; fail=1; return ;;
    esac
    local ok=1 kw
    if [ "$RC" -ne "$exp_rc" ]; then
        echo "FEHLER: erwarteter Exit $exp_rc, aber $RC" >&2
        printf '%s\n' "$OUT" >&2
        ok=0
    fi
    for kw in "$@"; do
        if ! printf '%s' "$OUT" | grep -qF -- "$kw"; then
            echo "FEHLER: Stichwort „$kw” nicht in der Ausgabe" >&2
            ok=0
        fi
    done
    [ "$ok" -eq 1 ] || fail=1
}

expect_not() {
    local exp_rc="$1"; shift
    case "$exp_rc" in
        ''|*[!0-9]*) echo "FEHLER: ${FUNCNAME[0]} ohne Exit-Code aufgerufen: $exp_rc" >&2; fail=1; return ;;
    esac
    local ok=1 kw
    if [ "$RC" -ne "$exp_rc" ]; then
        echo "FEHLER: erwarteter Exit $exp_rc, aber $RC" >&2
        printf '%s\n' "$OUT" >&2
        ok=0
    fi
    for kw in "$@"; do
        if printf '%s' "$OUT" | grep -qF -- "$kw"; then
            echo "FEHLER: Stichwort „$kw” nicht erwartet" >&2
            ok=0
        fi
    done
    [ "$ok" -eq 1 ] || fail=1
}

new_repo() {
    local d
    d="$(mktemp -d)"
    TMPDIRS+=("$d")
    git -C "$d" init -q -b main
    git -C "$d" config user.email "t@t"
    git -C "$d" config user.name "t"
    git -C "$d" config commit.gpgsign false
    printf '%s\n' "$d"
}

writef() {  # writef <dir> <path> <content-with-%b-escapes>
    local d="$1" p="$2" c="$3"
    mkdir -p "$d/$(dirname "$p")"
    printf '%b' "$c" > "$d/$p"
}

write_php() {  # write_php <dir> <path>  (Inhalt über quoted Heredoc, literal)
    local d="$1" p="$2"
    mkdir -p "$d/$(dirname "$p")"
    cat > "$d/$p"
}

commit_base() {  # commit_base <dir> <message>
    git -C "$1" add -A
    git -C "$1" commit -q -m "$2"
}

# --- gute neue Migration: CREATE TABLE, down vorhanden → 0 ---
d="$(new_repo)"
writef "$d" "README.md" "hello\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
write_php "$d" "migrations/VersionGood.php" <<'EOF'
<?php

final class VersionGood extends \Doctrine\Migrations\AbstractMigration {
    public function up(): void {
        $this->addSql('CREATE TABLE users (id integer PRIMARY KEY, name varchar(255) NOT NULL)');
    }
    public function down(): void {
        $this->executeSql('DROP TABLE users');
    }
}
EOF
git -C "$d" add -A
git -C "$d" commit -q -m "gute Migration"
run_script "$d" main
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"

# --- M1: use App\Entity\ / Repository / getRepository / EntityManager → 1 ---
d="$(new_repo)"
writef "$d" "README.md" "hello\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
write_php "$d" "migrations/VersionM1.php" <<'EOF'
<?php

use App\Entity\User;
use App\Repository\UserRepository;

final class VersionM1 extends \Doctrine\Migrations\AbstractMigration {
    public function up(): void {
        $repo = $this->registry->getRepository(User::class);
        $em = \Doctrine\EntityManager::class;
        $this->addSql('CREATE TABLE users (id integer PRIMARY KEY)');
    }
    public function down(): void {
        $this->executeSql('DROP TABLE users');
    }
}
EOF
git -C "$d" add -A
git -C "$d" commit -q -m "Migration mit Entity-Bezug"
run_script "$d" main
expect 1 "Entities/Repositories"

# --- M2: ADD ... NOT NULL ohne DEFAULT → 1 ---
d="$(new_repo)"
writef "$d" "README.md" "hello\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
write_php "$d" "migrations/VersionM2.php" <<'EOF'
<?php

final class VersionM2 extends \Doctrine\Migrations\AbstractMigration {
    public function up(): void {
        $this->addSql('ALTER TABLE users ADD role integer NOT NULL');
    }
    public function down(): void {
        $this->executeSql('ALTER TABLE users DROP COLUMN role');
    }
}
EOF
git -C "$d" add -A
printf 'DATABASE_URL="postgresql://app:pw@db:5432/app"\n' > "$d/.env"
git -C "$d" add -A
git -C "$d" commit -q -m "Migration NOT NULL ohne DEFAULT"
run_script "$d" main
expect 1 "NOT NULL ohne DEFAULT" "PostgreSQL"
# dieselbe Migration unter MySQL/MariaDB: nur Hinweis
printf 'DATABASE_URL="mysql://app:pw@db:3306/app"\n' > "$d/.env"
git -C "$d" commit -q -am "MySQL"
run_script "$d" main
expect 0 "MySQL/MariaDB" "Keine Befunde."

# --- mehrzeiliges DELETE mit WHERE in der Folgezeile; DROP/DELETE nur in down() → 0 ---
d="$(new_repo)"
writef "$d" "README.md" "hello\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
write_php "$d" "migrations/VersionMulti.php" <<'PHP'
<?php

final class VersionMulti extends \Doctrine\Migrations\AbstractMigration {
    public function up(): void {
        $this->addSql(
            'DELETE FROM order_item
             WHERE order_id IN (SELECT id FROM kandidaten)'
        );
    }
    public function down(): void {
        $this->addSql('DELETE FROM order_item');
        $this->addSql('ALTER TABLE users DROP COLUMN role');
    }
}
PHP
git -C "$d" add -A
git -C "$d" commit -q -m "mehrzeilig"
run_script "$d" main
expect 0 "Keine Befunde."
expect_not 0 "Expand-Contract" "BEFUND"

# --- M2: dieselbe Anweisung mit DEFAULT 0 → 0 ---
d="$(new_repo)"
writef "$d" "README.md" "hello\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
write_php "$d" "migrations/VersionM2.php" <<'EOF'
<?php

final class VersionM2 extends \Doctrine\Migrations\AbstractMigration {
    public function up(): void {
        $this->addSql('ALTER TABLE users ADD role integer NOT NULL DEFAULT 0');
    }
    public function down(): void {
        $this->executeSql('ALTER TABLE users DROP COLUMN role');
    }
}
EOF
git -C "$d" add -A
git -C "$d" commit -q -m "Migration NOT NULL mit DEFAULT"
run_script "$d" main
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"

# --- M3: DROP COLUMN (Expand-Contract) → Hinweis, kein Befund → 0 ---
d="$(new_repo)"
writef "$d" "README.md" "hello\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
write_php "$d" "migrations/VersionM3.php" <<'EOF'
<?php

final class VersionM3 extends \Doctrine\Migrations\AbstractMigration {
    public function up(): void {
        $this->addSql('ALTER TABLE users ADD role integer NOT NULL DEFAULT 0');
        $this->addSql('ALTER TABLE users DROP COLUMN old_col');
    }
    public function down(): void {
        $this->executeSql('CREATE TABLE users (id integer PRIMARY KEY)');
    }
}
EOF
git -C "$d" add -A
git -C "$d" commit -q -m "Migration mit DROP COLUMN"
run_script "$d" main
expect 0 "Expand-Contract"

# --- M4: down() nur throw → Hinweis, kein Befund → 0 ---
d="$(new_repo)"
writef "$d" "README.md" "hello\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
write_php "$d" "migrations/VersionM4.php" <<'EOF'
<?php

final class VersionM4 extends \Doctrine\Migrations\AbstractMigration {
    public function up(): void {
        $this->addSql('CREATE TABLE users (id integer PRIMARY KEY)');
    }
    public function down(): void {
        $this->throwIrreversibleMigrationException();
    }
}
EOF
git -C "$d" add -A
git -C "$d" commit -q -m "Migration ohne umkehrbare down"
run_script "$d" main
expect 0 "umkehrbar"

# --- M5: DELETE FROM ohne WHERE → 1 ---
d="$(new_repo)"
writef "$d" "README.md" "hello\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
write_php "$d" "migrations/VersionM5.php" <<'EOF'
<?php

final class VersionM5 extends \Doctrine\Migrations\AbstractMigration {
    public function up(): void {
        $this->addSql('DELETE FROM users');
    }
    public function down(): void {
        $this->executeSql('CREATE TABLE users (id integer PRIMARY KEY)');
    }
}
EOF
git -C "$d" add -A
git -C "$d" commit -q -m "Migration DELETE ohne WHERE"
run_script "$d" main
expect 1 "alle Zeilen"

# --- M5: DELETE FROM mit WHERE → 0 ---
d="$(new_repo)"
writef "$d" "README.md" "hello\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
write_php "$d" "migrations/VersionM5b.php" <<'EOF'
<?php

final class VersionM5b extends \Doctrine\Migrations\AbstractMigration {
    public function up(): void {
        $this->addSql('DELETE FROM users WHERE id = 1');
    }
    public function down(): void {
        $this->executeSql('CREATE TABLE users (id integer PRIMARY KEY)');
    }
}
EOF
git -C "$d" add -A
git -C "$d" commit -q -m "Migration DELETE mit WHERE"
run_script "$d" main
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"

# --- alte Migration (in Basis vorhanden) mit M1 → 0 ---
d="$(new_repo)"
writef "$d" "README.md" "hello\n"
git -C "$d" checkout -q -b main
write_php "$d" "migrations/VersionOld.php" <<'EOF'
<?php

use App\Entity\User;

final class VersionOld extends \Doctrine\Migrations\AbstractMigration {
    public function up(): void {
        $this->addSql('CREATE TABLE users (id integer PRIMARY KEY)');
    }
    public function down(): void {
        $this->executeSql('DROP TABLE users');
    }
}
EOF
commit_base "$d" "Basis mit alter Migration"
git -C "$d" checkout -q -b feature
run_script "$d" main
expect 0 "keine neuen Migrationen"

# --- neue (unversionierte) Migration mit M5 (UPDATE ohne WHERE) → 1 ---
d="$(new_repo)"
writef "$d" "README.md" "hello\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
write_php "$d" "migrations/VersionUnversioned.php" <<'EOF'
<?php

final class VersionUnversioned extends \Doctrine\Migrations\AbstractMigration {
    public function up(): void {
        $this->addSql('UPDATE users SET active = 0');
    }
    public function down(): void {
        $this->executeSql('CREATE TABLE users (id integer PRIMARY KEY)');
    }
}
EOF
run_script "$d" main
expect 1 "alle Zeilen"

# --- kein migrations/ → 77 ---
d="$(new_repo)"
writef "$d" "src/App.php" "<?php\nclass App {}\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
run_script "$d" main
expect 77

# --- kein Git-Repo → 77 ---
d="$(mktemp -d)"
TMPDIRS+=("$d")
run_script "$d" main
expect 77

# --- basis-ref existiert nicht → 77 ---
d="$(new_repo)"
writef "$d" "src/App.php" "<?php\nclass App {}\n"
commit_base "$d" "Basis"
run_script "$d" kein-so-existiert-ref
expect 77

# --- ein Argument → 2 ---
d="$(new_repo)"
writef "$d" "src/App.php" "<?php\nclass App {}\n"
commit_base "$d" "Basis"
run_script "$d"
expect 2

# --- kein Argument → 2 ---
d="$(new_repo)"
writef "$d" "src/App.php" "<?php\nclass App {}\n"
commit_base "$d" "Basis"
run_script
expect 2

if [ "$fail" -eq 0 ]; then
    echo "OK: alle Fälle bestanden"
    exit 0
fi
echo "FEHLER: einige Fälle haben nicht bestanden" >&2
exit 1
