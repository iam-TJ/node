-include config.mk

BUILDTYPE ?= Release
PYTHON ?= python
NINJA ?= ninja
DESTDIR ?=
SIGN ?=
# Default build output directory. Change this to do out-of-tree builds
OUTDIR ?= out

# Default to verbose builds.
# To do quiet/pretty builds, run `make V=` to set V to an empty string,
# or set the V environment variable to an empty string.
V ?= 1

# BUILDTYPE=Debug builds both release and debug builds. If you want to compile
# just the debug build, run `make -C $(OUTDIR) BUILDTYPE=Debug` instead.
ifeq ($(BUILDTYPE),Release)
all: $(OUTDIR)/Makefile $(OUTDIR)/../node
else
all: $(OUTDIR)/Makefile $(OUTDIR)/../node node_g
endif

# The .PHONY is needed to ensure that we recursively use the $(OUTDIR)/Makefile
# to check for changes.
.PHONY: node node_g

ifeq ($(USE_NINJA),1)
$(OUTDIR)/../node: config.gypi
	$(NINJA) -C $(OUTDIR)/Release/
	ln -fs $(OUTDIR)/Release/node $(OUTDIR)/../node

$(OUTDIR)/../node_g: config.gypi
	$(NINJA) -C $(OUTDIR)/Debug/
	ln -fs $(OUTDIR)/Debug/node $(OUTDIR)/../$@
else
$(OUTDIR)/../node: config.gypi $(OUTDIR)/Makefile
	$(MAKE) -C $(OUTDIR) BUILDTYPE=Release V=$(V)
	ln -fs $(OUTDIR)/Release/node $(OUTDIR)/../node

$(OUTDIR)/../node_g: config.gypi $(OUTDIR)/Makefile
	$(MAKE) -C $(OUTDIR) BUILDTYPE=Debug V=$(V)
	ln -fs $(OUTDIR)/Debug/node $(OUTDIR)/../$@
endif

$(OUTDIR)/Makefile: common.gypi deps/uv/uv.gyp deps/http_parser/http_parser.gyp deps/zlib/zlib.gyp deps/v8/build/common.gypi deps/v8/tools/gyp/v8.gyp node.gyp config.gypi
ifeq ($(USE_NINJA),1)
	touch $(OUTDIR)/Makefile
	$(PYTHON) tools/gyp_node -f ninja -O $(OUTDIR)
else
	$(PYTHON) tools/gyp_node -f make -O $(OUTDIR)
endif

config.gypi: configure
	$(PYTHON) ./configure

install: all
	$(PYTHON) tools/install.py $@ $(DESTDIR)

uninstall:
	$(PYTHON) tools/install.py $@ $(DESTDIR)

clean:
	-rm -rf $(OUTDIR)/Makefile node node_g $(OUTDIR)/$(BUILDTYPE)/node blog.html email.md
	-find $(OUTDIR)/ -name '*.o' -o -name '*.a' | xargs rm -rf
	-rm -rf node_modules

distclean:
	-rm -rf $(OUTDIR)
	-rm -f config.gypi
	-rm -f config.mk
	-rm -rf node node_g blog.html email.md
	-rm -rf node_modules

test: all
	$(PYTHON) tools/test.py --mode=release simple message
	$(MAKE) jslint

test-http1: all
	$(PYTHON) tools/test.py --mode=release --use-http1 simple message

test-valgrind: all
	$(PYTHON) tools/test.py --mode=release --valgrind simple message

test/gc/node_modules/weak/build:
	@if [ ! -f node ]; then make all; fi
	./node deps/npm/node_modules/node-gyp/bin/node-gyp rebuild \
		--directory="$(shell pwd)/test/gc/node_modules/weak" \
		--nodedir="$(shell pwd)"

test-gc: all test/gc/node_modules/weak/build
	$(PYTHON) tools/test.py --mode=release gc

test-all: all test/gc/node_modules/weak/build
	$(PYTHON) tools/test.py --mode=debug,release
	make test-npm

test-all-http1: all
	$(PYTHON) tools/test.py --mode=debug,release --use-http1

test-all-valgrind: all
	$(PYTHON) tools/test.py --mode=debug,release --valgrind

test-release: all
	$(PYTHON) tools/test.py --mode=release

test-debug: all
	$(PYTHON) tools/test.py --mode=debug

test-message: all
	$(PYTHON) tools/test.py message

test-simple: all
	$(PYTHON) tools/test.py simple

test-pummel: all
	$(PYTHON) tools/test.py pummel

test-internet: all
	$(PYTHON) tools/test.py internet

test-npm: node
	./node deps/npm/test/run.js

test-npm-publish: node
	npm_package_config_publishtest=true ./node deps/npm/test/run.js

apidoc_sources = $(wildcard doc/api/*.markdown)
apidocs = $(addprefix $(OUTDIR)/,$(apidoc_sources:.markdown=.html)) \
          $(addprefix $(OUTDIR)/,$(apidoc_sources:.markdown=.json))

apidoc_dirs = $(OUTDIR)/doc $(OUTDIR)/doc/api/ $(OUTDIR)/doc/api/assets $(OUTDIR)/doc/about $(OUTDIR)/doc/community $(OUTDIR)/doc/download $(OUTDIR)/doc/logos $(OUTDIR)/doc/images

apiassets = $(subst api_assets,api/assets,$(addprefix $(OUTDIR)/,$(wildcard doc/api_assets/*)))

doc_images = $(addprefix $(OUTDIR)/,$(wildcard doc/images/* doc/*.jpg doc/*.png))

website_files = \
	$(OUTDIR)/doc/index.html    \
	$(OUTDIR)/doc/v0.4_announcement.html   \
	$(OUTDIR)/doc/cla.html      \
	$(OUTDIR)/doc/sh_main.js    \
	$(OUTDIR)/doc/sh_javascript.min.js \
	$(OUTDIR)/doc/sh_vim-dark.css \
	$(OUTDIR)/doc/sh.css \
	$(OUTDIR)/doc/favicon.ico   \
	$(OUTDIR)/doc/pipe.css \
	$(OUTDIR)/doc/about/index.html \
	$(OUTDIR)/doc/community/index.html \
	$(OUTDIR)/doc/download/index.html \
	$(OUTDIR)/doc/logos/index.html \
	$(OUTDIR)/doc/changelog.html \
	$(doc_images)

doc: $(apidoc_dirs) $(website_files) $(apiassets) $(apidocs) tools/doc/ blog node

blogclean:
	rm -rf $(OUTDIR)/blog

blog: doc/blog $(OUTDIR)/Release/node tools/blog
	$(OUTDIR)/Release/node tools/blog/generate.js doc/blog/ $(OUTDIR)/blog/ doc/blog.html doc/rss.xml

$(apidoc_dirs):
	mkdir -p $@

$(OUTDIR)/doc/api/assets/%: doc/api_assets/% $(OUTDIR)/doc/api/assets/
	cp $< $@

$(OUTDIR)/doc/changelog.html: ChangeLog doc/changelog-head.html doc/changelog-foot.html tools/build-changelog.sh node
	bash tools/build-changelog.sh

$(OUTDIR)/doc/%.html: doc/%.html node
	cat $< | sed -e 's|__VERSION__|'$(VERSION)'|g' > $@

$(OUTDIR)/doc/%: doc/%
	cp -r $< $@

$(OUTDIR)/doc/api/%.json: doc/api/%.markdown node
	$(OUTDIR)/Release/node tools/doc/generate.js --format=json $< > $@

$(OUTDIR)/doc/api/%.html: doc/api/%.markdown node
	$(OUTDIR)/Release/node tools/doc/generate.js --format=html --template=doc/template.html $< > $@

email.md: ChangeLog tools/email-footer.md
	bash tools/changelog-head.sh | sed 's|^\* #|* \\#|g' > $@
	cat tools/email-footer.md | sed -e 's|__VERSION__|'$(VERSION)'|g' >> $@

blog.html: email.md
	cat $< | ./node tools/doc/node_modules/.bin/marked > $@

blog-upload: blog
	rsync -r $(OUTDIR)/blog/ node@nodejs.org:~/web/nodejs.org/blog/

website-upload: doc
	rsync -r $(OUTDIR)/doc/ node@nodejs.org:~/web/nodejs.org/
	ssh node@nodejs.org '\
    rm -f ~/web/nodejs.org/dist/latest &&\
    ln -s $(VERSION) ~/web/nodejs.org/dist/latest &&\
    rm -f ~/web/nodejs.org/docs/latest &&\
    ln -s $(VERSION) ~/web/nodejs.org/docs/latest &&\
    rm -f ~/web/nodejs.org/dist/node-latest.tar.gz &&\
    ln -s $(VERSION)/node-$(VERSION).tar.gz ~/web/nodejs.org/dist/node-latest.tar.gz'

docopen: $(OUTDIR)/doc/api/all.html
	-google-chrome $(OUTDIR)/doc/api/all.html

docclean:
	-rm -rf $(OUTDIR)/doc

VERSION=v$(shell $(PYTHON) tools/getnodeversion.py)
RELEASE=$(shell $(PYTHON) tools/getnodeisrelease.py)
PLATFORM=$(shell uname | tr '[:upper:]' '[:lower:]')
ifeq ($(findstring x86_64,$(shell uname -m)),x86_64)
DESTCPU ?= x64
else
DESTCPU ?= ia32
endif
ifeq ($(DESTCPU),x64)
ARCH=x64
else
ifeq ($(DESTCPU),arm)
ARCH=arm
else
ARCH=x86
endif
endif
TARNAME=node-$(VERSION)
TARBALL=$(TARNAME).tar.gz
BINARYNAME=$(TARNAME)-$(PLATFORM)-$(ARCH)
BINARYTAR=$(BINARYNAME).tar.gz
PKG=$(OUTDIR)/$(TARNAME).pkg
packagemaker=/Developer/Applications/Utilities/PackageMaker.app/Contents/MacOS/PackageMaker

dist: doc $(TARBALL) $(PKG)

PKGDIR=$(OUTDIR)/dist-osx

release-only:
	@if [ "$(shell git status --porcelain | egrep -v '^\?\? ')" = "" ]; then \
		exit 0 ; \
	else \
	  echo "" >&2 ; \
		echo "The git repository is not clean." >&2 ; \
		echo "Please commit changes before building release tarball." >&2 ; \
		echo "" >&2 ; \
		git status --porcelain | egrep -v '^\?\?' >&2 ; \
		echo "" >&2 ; \
		exit 1 ; \
	fi
	@if [ "$(RELEASE)" = "1" ]; then \
		exit 0; \
	else \
	  echo "" >&2 ; \
		echo "#NODE_VERSION_IS_RELEASE is set to $(RELEASE)." >&2 ; \
	  echo "Did you remember to update src/node_version.cc?" >&2 ; \
	  echo "" >&2 ; \
		exit 1 ; \
	fi

pkg: $(PKG)

$(PKG): release-only
	rm -rf $(PKGDIR)
	rm -rf $(OUTDIR)/deps $(OUTDIR)/Release
	$(PYTHON) ./configure --prefix=$(PKGDIR)/32/usr/local --without-snapshot --dest-cpu=ia32
	$(MAKE) install V=$(V)
	rm -rf $(OUTDIR)/deps $(OUTDIR)/Release
	$(PYTHON) ./configure --prefix=$(PKGDIR)/usr/local --without-snapshot --dest-cpu=x64
	$(MAKE) install V=$(V)
	SIGN="$(SIGN)" PKGDIR="$(PKGDIR)" bash tools/osx-codesign.sh
	lipo $(PKGDIR)/32/usr/local/bin/node \
		$(PKGDIR)/usr/local/bin/node \
		-output $(PKGDIR)/usr/local/bin/node-universal \
		-create
	mv $(PKGDIR)/usr/local/bin/node-universal $(PKGDIR)/usr/local/bin/node
	rm -rf $(PKGDIR)/32
	$(packagemaker) \
		--id "org.nodejs.Node" \
		--doc tools/osx-pkg.pmdoc \
		--out $(PKG)
	SIGN="$(SIGN)" PKG="$(PKG)" bash tools/osx-productsign.sh

$(TARBALL): release-only node doc
	git archive --format=tar --prefix=$(TARNAME)/ HEAD | tar xf -
	mkdir -p $(TARNAME)/doc/api
	cp doc/node.1 $(TARNAME)/doc/node.1
	cp -r $(OUTDIR)/doc/api/* $(TARNAME)/doc/api/
	rm -rf $(TARNAME)/deps/v8/test # too big
	rm -rf $(TARNAME)/doc/images # too big
	find $(TARNAME)/ -type l | xargs rm # annoying on windows
	tar -cf $(TARNAME).tar $(TARNAME)
	rm -rf $(TARNAME)
	gzip -f -9 $(TARNAME).tar

tar: $(TARBALL)

$(BINARYTAR): release-only
	rm -rf $(BINARYNAME)
	rm -rf $(OUTDIR)/deps $(OUTDIR)/Release
	$(PYTHON) ./configure --prefix=/ --without-snapshot --dest-cpu=$(DESTCPU) $(CONFIG_FLAGS)
	$(MAKE) install DESTDIR=$(BINARYNAME) V=$(V) PORTABLE=1
	cp README.md $(BINARYNAME)
	cp LICENSE $(BINARYNAME)
	cp ChangeLog $(BINARYNAME)
	tar -cf $(BINARYNAME).tar $(BINARYNAME)
	rm -rf $(BINARYNAME)
	gzip -f -9 $(BINARYNAME).tar

binary: $(BINARYTAR)

dist-upload: $(TARBALL) $(PKG)
	ssh node@nodejs.org mkdir -p web/nodejs.org/dist/$(VERSION)
	scp $(TARBALL) node@nodejs.org:~/web/nodejs.org/dist/$(VERSION)/$(TARBALL)
	scp $(PKG) node@nodejs.org:~/web/nodejs.org/dist/$(VERSION)/$(TARNAME).pkg

bench:
	 benchmark/http_simple_bench.sh

bench-idle:
	./node benchmark/idle_server.js &
	sleep 1
	./node benchmark/idle_clients.js &

jslintfix:
	PYTHONPATH=tools/closure_linter/ $(PYTHON) tools/closure_linter/closure_linter/fixjsstyle.py --strict --nojsdoc -r lib/ -r src/ --exclude_files lib/punycode.js

jslint:
	PYTHONPATH=tools/closure_linter/ $(PYTHON) tools/closure_linter/closure_linter/gjslint.py --unix_mode --strict --nojsdoc -r lib/ -r src/ --exclude_files lib/punycode.js

cpplint:
	@$(PYTHON) tools/cpplint.py $(wildcard src/*.cc src/*.h src/*.c)

lint: jslint cpplint

.PHONY: lint cpplint jslint bench clean docopen docclean doc dist distclean check uninstall install install-includes install-bin all staticlib dynamiclib test test-all website-upload pkg blog blogclean tar binary release-only
