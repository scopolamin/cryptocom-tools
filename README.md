# cryptocom-tools

## Usage

```
./cryptocom.sh --action redelegate --passphrase 'YOUR_PASSPHRASE'
```

## Crontab

```
*/2 * * * * /bin/bash /home/deploy/crypto_com/croeseid-2/cryptocom.sh --action redelegate --passphrase 'YOUR_PASSPHRASE' > /dev/null 2>&1
```
