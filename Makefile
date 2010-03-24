# Tagger makefile
# 
# Created by Ali Rantakari on 25 June, 2008
# 

SHELL=/bin/bash

APP_VERSION=$(shell /usr/libexec/PlistBuddy -c "Print CFBundleVersion" ./build/Release/Tagger.app/Contents/Info.plist)
deploy : LATEST_APP_VERSION=$(shell curl -s http://hasseg.org/tagger/?versioncheck=y)

TEMP_DEPLOYMENT_DIR=deployment/$(APP_VERSION)
TEMP_DEPLOYMENT_ZIPFILE=$(TEMP_DEPLOYMENT_DIR)/Tagger-v$(APP_VERSION).zip
TEMP_DEPLOYMENT_FASCRIPTS="deployment/frontAppScripts.html"
VERSIONCHANGELOGFILELOC="$(TEMP_DEPLOYMENT_DIR)/changelog.html"
GENERALCHANGELOGFILELOC="changelog.html"
SCP_TARGET=$(shell cat ./deploymentScpTarget)

SPARKLE_PRIVATE_KEY_FILE_PATH=$(shell cat ./pathToSparklePrivateKey)
SPARKLE_TEMP_DEPLOYMENT_ZIPFILE=$(TEMP_DEPLOYMENT_DIR)/Tagger-v$(APP_VERSION)-sparkle.zip
SPARKLE_DSA_SIGNATURE_FILE=$(TEMP_DEPLOYMENT_DIR)/dsa-signature

DEPLOYMENT_INCLUDES_DIR="deployment-files"







#-------------------------------------------------------------------------
#-------------------------------------------------------------------------
# generate documentation
#-------------------------------------------------------------------------
docs: frontAppScripts.markdown
	@echo
	@echo ---- Generating HTML from frontAppScripts.markdown:
	@echo ======================================
	echo "<html><head><title>Tagger Front Application Scripts</title>" > $(TEMP_DEPLOYMENT_FASCRIPTS)
	echo "<style type='text/css'>#main{width:600px; margin:30 auto 300 auto;} h2{margin-top:30px;} pre{border:1px solid black;background:#eee;padding:10px;display:inline-block;margin:0;}</style>" >> $(TEMP_DEPLOYMENT_FASCRIPTS)
	echo "</head><body><div id='main'>" >> $(TEMP_DEPLOYMENT_FASCRIPTS)
	perl utils/markdown/Markdown.pl frontAppScripts.markdown >> $(TEMP_DEPLOYMENT_FASCRIPTS)
	echo "</div></body></html>" >> $(TEMP_DEPLOYMENT_FASCRIPTS)





#-------------------------------------------------------------------------
#-------------------------------------------------------------------------
# make release package (prepare for deployment)
#-------------------------------------------------------------------------
release: docs
	@echo
	@echo ---- Preparing for deployment:
	@echo ======================================
	
	cp frontAppScripts.markdown deployment-files/frontAppScripts-readme.txt
	
# create zip archive
	mkdir -p $(TEMP_DEPLOYMENT_DIR)
	cd "./build/Release/"; echo "-g -r ../../$(TEMP_DEPLOYMENT_ZIPFILE) \"Tagger.app\"" | xargs zip > /dev/null
	cd "$(DEPLOYMENT_INCLUDES_DIR)"; echo "-g -R ../$(TEMP_DEPLOYMENT_ZIPFILE) *" | xargs zip > /dev/null
	
# create "sparkle distribution" zip archive
	cd "./build/Release/"; echo "-r ../../$(SPARKLE_TEMP_DEPLOYMENT_ZIPFILE) \"Tagger.app\"" | xargs zip > /dev/null

# create DSA signature for "sparkle distribution" zip archive
	ruby utils/sign_update.rb "$(SPARKLE_TEMP_DEPLOYMENT_ZIPFILE)" "$(SPARKLE_PRIVATE_KEY_FILE_PATH)" > "$(SPARKLE_DSA_SIGNATURE_FILE)"
	
# if changelog doesn't already exist in the deployment dir
# for this version, get 'general' changelog file from root if
# one exists, and if not, create an empty changelog file
	@( if [ ! -e $(VERSIONCHANGELOGFILELOC) ];then\
		if [ -e $(GENERALCHANGELOGFILELOC) ];then\
			cp $(GENERALCHANGELOGFILELOC) $(VERSIONCHANGELOGFILELOC);\
			echo "Copied existing changelog.html from project root into deployment dir - opening it for editing";\
		else\
			echo "<ul>\
		<li></li>\
	</ul>\
	" > $(VERSIONCHANGELOGFILELOC);\
			echo "Created new empty changelog.html into deployment dir - opening it for editing";\
		fi; \
	else\
		echo "changelog.html exists for $(APP_VERSION) - opening it for editing";\
	fi )
	@open -a Smultron $(VERSIONCHANGELOGFILELOC)




#-------------------------------------------------------------------------
#-------------------------------------------------------------------------
# deploy to server
#-------------------------------------------------------------------------
deploy: release
	@echo
	@echo ---- Deploying to server:
	@echo ======================================
	
	@( if [ "$(LATEST_APP_VERSION)" != "$(APP_VERSION)" ];then\
		echo "Latest version on server is $(LATEST_APP_VERSION). Uploading $(APP_VERSION).";\
	else\
		echo "NOTE: Current version exists on server: ($(APP_VERSION)).";\
	fi;\
	echo "Press enter to continue uploading to server or Ctrl-C to cancel.";\
	read INPUTSTR;\
	scp -r $(TEMP_DEPLOYMENT_DIR) $(TEMP_DEPLOYMENT_FASCRIPTS) $(SCP_TARGET); )




#-------------------------------------------------------------------------
#-------------------------------------------------------------------------
clean:
	@echo
	@echo ---- Cleaning up:
	@echo ======================================
	-rm -Rf deployment/*
	-rm -Rf "deployment-files/frontAppScripts-readme.txt"



