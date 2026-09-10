# docs/

Документы здесь хранятся **зашифрованными** — файлы `*.md.sops`. Открытых `.md`
в git нет, они в `.gitignore`.

Репозиторий публичный. Секретов в документах нет, но есть подробное описание
инфраструктуры: какие ноды что несут, как именно ломался кластер и почему,
что осталось незакрытым. Код читать полезно всем, это — не всем.

Прочитать:

    export SOPS_AGE_KEY_FILE=~/Документы/argocd-apps/.age/age.key
    sops -d --input-type json --output-type binary docs/<имя>.md.sops > docs/<имя>.md

Записать обратно:

    sops -e --input-type binary --output-type json docs/<имя>.md > docs/<имя>.md.sops
