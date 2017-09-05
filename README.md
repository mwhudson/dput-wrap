This is a wrapper around dput that checks for various silly mistakes I
have a tendency to make, e.g. forgetting to tag ppa uploads with \~ppa
in the version or uploading foo_1.2.3-1ubunut1\~16.04 to zesty.

I might investigate integrating this into dput-ng at some point.

Example usage:

```
mwhudson@aeglos:/opt/opensource/deb/docker$ dput-wrap.pl docker.io_1.13.1-0ubuntu1~17.04.1_source.changes
no [~+]16.04 in version for upload targeting xenial, found ~17.04 though
mwhudson@aeglos:/opt/opensource/deb/docker$ dput-wrap.pl runc_1.0.0~rc2+docker1.12.6-0ubuntu1~16.04.1_source.changes
bug 1675288 has task for xenial/runc with unsuitable status Fix Released
```
