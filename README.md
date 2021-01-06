# cryptocom-tools

## Usage

### Status

```
./cryptocom.sh --action status --passphrase 'YOUR_PASSPHRASE'
```

### Redelegation

```
./cryptocom.sh --action redelegate --passphrase 'YOUR_PASSPHRASE'
```

## Crontab

```
*/2 * * * * /bin/bash /home/deploy/crypto_com/croeseid-2/cryptocom.sh --action redelegate --passphrase 'YOUR_PASSPHRASE' > /dev/null 2>&1
```
