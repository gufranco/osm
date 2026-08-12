complete -c osm -f
complete -c osm -n __fish_use_subcommand -a send -d 'encrypt a message to a user'
complete -c osm -n __fish_use_subcommand -a read -d 'decrypt a message'
complete -c osm -n __fish_use_subcommand -a keys -d 'list the keys a user publishes'
complete -c osm -n __fish_use_subcommand -a doctor -d 'check the local environment'
complete -c osm -n __fish_use_subcommand -a version -d 'print the version and engine'

complete -c osm -n '__fish_seen_subcommand_from send' -l to -r -d 'add a recipient'
complete -c osm -n '__fish_seen_subcommand_from send' -l keys-file -r -F -d 'recipients from a key file'
complete -c osm -n '__fish_seen_subcommand_from send' -l key -r -d 'pin one key by fingerprint prefix'
complete -c osm -n '__fish_seen_subcommand_from send' -l sign -r -d 'sign as a user you hold a key for'
complete -c osm -n '__fish_seen_subcommand_from send' -l json -d 'machine readable output'
complete -c osm -n '__fish_seen_subcommand_from send' -l qr -d 'print as a QR code'
complete -c osm -n '__fish_seen_subcommand_from send' -l accept-new-key -d 'accept changed recipient keys'
complete -c osm -n '__fish_seen_subcommand_from send' -l no-clipboard -d 'do not copy to the clipboard'

complete -c osm -n '__fish_seen_subcommand_from read' -l identity -r -F -d 'decrypt with a specific key'
complete -c osm -n '__fish_seen_subcommand_from read' -l clipboard -d 'read from the clipboard'
complete -c osm -n '__fish_seen_subcommand_from read' -l require-signature -d 'refuse an unsigned message'
