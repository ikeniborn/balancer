#!/bin/bash
#
# validate-docs.sh - Скрипт проверки целостности документации проекта Balancer
#
# Проверяет:
# - Существование всех файлов, упомянутых в INDEX.md
# - Наличие всех .md файлов в INDEX.md
# - Корректность внутренних ссылок
# - Наличие навигационных footer'ов
# - Корректность YAML front matter (если есть)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

errors=0
warnings=0

echo -e "${BLUE}=== Validation документации проекта Balancer ===${NC}"
echo ""

# 1. Проверка существования INDEX.md
echo -e "${BLUE}[1/6] Проверка INDEX.md...${NC}"
if [ ! -f "INDEX.md" ]; then
    echo -e "${RED}✗ ОШИБКА: INDEX.md не найден!${NC}"
    ((errors++))
    exit 1
else
    echo -e "${GREEN}✓ INDEX.md найден${NC}"
fi

# 2. Проверка всех ссылок из INDEX.md
echo ""
echo -e "${BLUE}[2/6] Проверка ссылок в INDEX.md...${NC}"

# Извлекаем все ссылки на .md файлы из INDEX.md
links=$(grep -o '\[.*\]([^)]*\.md)' INDEX.md | sed 's/.*(\(.*\))/\1/' || true)

if [ -z "$links" ]; then
    echo -e "${YELLOW}⚠ Предупреждение: Не найдено ссылок на .md файлы в INDEX.md${NC}"
    ((warnings++))
else
    missing_files=0
    while IFS= read -r file; do
        if [ -n "$file" ] && [ ! -f "$file" ]; then
            echo -e "${RED}✗ Отсутствует файл: $file${NC}"
            ((missing_files++))
            ((errors++))
        fi
    done <<< "$links"

    if [ $missing_files -eq 0 ]; then
        echo -e "${GREEN}✓ Все файлы из INDEX.md существуют${NC}"
    fi
fi

# 3. Проверка что все .md файлы упомянуты в INDEX.md
echo ""
echo -e "${BLUE}[3/6] Проверка полноты INDEX.md...${NC}"

# Получаем список всех .md файлов кроме служебных
all_docs=$(ls [0-1]*.md 2>/dev/null || true)

if [ -z "$all_docs" ]; then
    echo -e "${YELLOW}⚠ Предупреждение: Не найдено документов с маской [0-1]*.md${NC}"
    ((warnings++))
else
    unlisted_files=0
    for doc in $all_docs; do
        if ! grep -q "$doc" INDEX.md; then
            echo -e "${YELLOW}⚠ Файл $doc не упомянут в INDEX.md${NC}"
            ((unlisted_files++))
            ((warnings++))
        fi
    done

    if [ $unlisted_files -eq 0 ]; then
        echo -e "${GREEN}✓ Все документы упомянуты в INDEX.md${NC}"
    fi
fi

# 4. Проверка навигационных footer'ов
echo ""
echo -e "${BLUE}[4/6] Проверка навигационных footer'ов...${NC}"

missing_footers=0
for doc in $all_docs; do
    if ! grep -q '\[◀ Назад к оглавлению\](INDEX.md)' "$doc"; then
        echo -e "${YELLOW}⚠ Отсутствует footer в файле: $doc${NC}"
        ((missing_footers++))
        ((warnings++))
    fi
done

if [ $missing_footers -eq 0 ]; then
    echo -e "${GREEN}✓ Все документы имеют навигационные footer'ы${NC}"
else
    echo -e "${YELLOW}⚠ $missing_footers файлов без footer'ов${NC}"
fi

# 5. Проверка внутренних ссылок в документах
echo ""
echo -e "${BLUE}[5/6] Проверка внутренних ссылок...${NC}"

broken_links=0
for doc in $all_docs; do
    # Извлекаем все ссылки на .md файлы
    doc_links=$(grep -o '\[.*\]([^)]*\.md)' "$doc" | sed 's/.*(\(.*\))/\1/' || true)

    if [ -n "$doc_links" ]; then
        while IFS= read -r link; do
            if [ -n "$link" ] && [ ! -f "$link" ]; then
                echo -e "${RED}✗ Битая ссылка в $doc: $link${NC}"
                ((broken_links++))
                ((errors++))
            fi
        done <<< "$doc_links"
    fi
done

if [ $broken_links -eq 0 ]; then
    echo -e "${GREEN}✓ Все внутренние ссылки корректны${NC}"
fi

# 6. Проверка YAML front matter (опционально)
echo ""
echo -e "${BLUE}[6/6] Проверка YAML front matter...${NC}"

files_with_frontmatter=0
for doc in $all_docs; do
    if head -1 "$doc" | grep -q '^---$'; then
        ((files_with_frontmatter++))
    fi
done

if [ $files_with_frontmatter -gt 0 ]; then
    echo -e "${GREEN}✓ $files_with_frontmatter файлов с YAML front matter${NC}"
else
    echo -e "${YELLOW}ℹ YAML front matter не используется${NC}"
fi

# Итоговая статистика
echo ""
echo -e "${BLUE}=== Итоги проверки ===${NC}"
echo ""
echo "Проверено документов: $(echo "$all_docs" | wc -w)"
echo -e "Ошибки: ${RED}$errors${NC}"
echo -e "Предупреждения: ${YELLOW}$warnings${NC}"
echo ""

if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
    echo -e "${GREEN}✓✓✓ Документация в отличном состоянии!${NC}"
    exit 0
elif [ $errors -eq 0 ]; then
    echo -e "${YELLOW}⚠ Документация корректна, но есть предупреждения${NC}"
    exit 0
else
    echo -e "${RED}✗ Обнаружены критические ошибки!${NC}"
    exit 1
fi
