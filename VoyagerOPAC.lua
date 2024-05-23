local settings = {}
settings.OpacUrl = GetSetting("OPACURL");
settings.Tomcat =  GetSetting("TomcatWebvoyage");
settings.LocationLabelClass =  GetSetting("TomcatLocationLabelSpanClass");
settings.LocationValueClass =  GetSetting("TomcatLocationValueSpanClass");
settings.CallNumberLabelClass =  GetSetting("TomcatCallNumberLabelSpanClass");
settings.CallNumberValueClass =  GetSetting("TomcatCallNumberValueSpanClass");
settings.ClassicKeywordValue = GetSetting("ClassicKeywordValue");

local interfaceMngr = nil;
local opacForm = {};
opacForm.Form = nil;
opacForm.RibbonPage = nil;
opacForm.Browser = nil;

local searchTerm = nil;
local searchCode = nil;
local searchBox = "querybox";

function Init()
    interfaceMngr = GetInterfaceManager();

	-- Create a form
	opacForm.Form = interfaceMngr:CreateForm("OPAC Search", "Script");

	-- Add a browser
	opacForm.Browser = opacForm.Form:CreateBrowser("OPAC Search", "OPAC Search Browser", "OPAC Search", "WebView2");

	-- Hide the text label
	opacForm.Browser.TextVisible = false;

	-- Since we didn't create a ribbon explicitly before creating our browser, it will have created one using the name we passed the CreateBrowser method.  We can retrieve that one and add our buttons to it.
	opacForm.RibbonPage = opacForm.Form:GetRibbonPage("OPAC Search");

	-- Create the search and import buttons.
	opacForm.RibbonPage:CreateButton("Search Keyword", GetClientImage("Search32"), "SearchKeyword", "OPAC");
    opacForm.RibbonPage:CreateButton("Search Title", GetClientImage("Search32"), "SearchTitle", "OPAC");

	-- Set the SearchForm
	if settings.Tomcat == false then
		searchBox = "querybox";
		opacForm.RibbonPage:CreateButton("Import Info", GetClientImage("Search32"), "ImportInfo", "OPAC");
	else
		searchBox = "searchBasic";
	end

	-- After we add all of our buttons and form elements, we can show the form.
	opacForm.Form:Show();

    SearchTitle();
end

function SetSearchTerm()
	if GetFieldValue("Transaction", "RequestType") == "Loan" then
		searchTerm = GetFieldValue("Transaction", "LoanTitle");
	else
		searchTerm = GetFieldValue("Transaction", "PhotoJournalTitle");
	end
end

function SearchKeyword()

	SetSearchTerm();

	if settings.Tomcat == false then
		searchCode = settings.ClassicKeywordValue;
	else
		searchCode = "GKEY^*";
	end

	opacForm.Browser:RegisterPageHandler("formExists", searchBox , "OPACLoaded", true);
	opacForm.Browser:Navigate(settings.OpacUrl);
end

function SearchTitle()

	SetSearchTerm();

	if GetFieldValue("Transaction", "RequestType") == "Loan" then
		searchCode = "TALL";
    else
		searchCode = "JALL";
    end

	opacForm.Browser:RegisterPageHandler("formExists", searchBox, "OPACLoaded", true);
	opacForm.Browser:Navigate(settings.OpacUrl);
end

function OPACLoaded()
	LogDebug("OPAC Loaded");

	local scriptArgs = {settings.Tomcat, searchBox, searchTerm, searchCode};
	local searchFormScript = [[
		(function (useTomcat, searchBox, searchTerm, searchCode) {
			if (useTomcat == false){
				document.getElementById("Search_Arg").value = searchTerm;
				document.getElementById("Search_Code").value = searchCode;

				document.getElementsByName(searchBox)[0].submit();
			}
			else{
				document.getElementById("searchArg").value = searchTerm;
				document.getElementById("searchCode").value = searchCode;

				document.getElementById(searchBox).submit();
			}
		})
	]];

	if settings.Tomcat then
		opacForm.Browser:RegisterPageHandler("custom", "CheckHoldingsPageLoaded", "HoldingsPageLoaded", false);
	end

	opacForm.Browser:ExecuteScript(searchFormScript, scriptArgs);
end

function ImportInfo()
	if settings.Tomcat == false then
		ImportInfoClassic();
	end
end

function ImportInfoClassic()
	local importInfoClassicScript = [[
		var detailsTable = document.getElementsByTagName("Table")[1];
		var detailRows = detailsTable.getElementsByTagName("TR");
		
		window.chrome.webview.hostObjects.sync.atlasAddon.ExecuteAddonFunction("LogDebug", "Found " + detailRows.length + " rows.");
		
		for (let row of detailRows){
			window.chrome.webview.hostObjects.sync.atlasAddon.ExecuteAddonFunction("LogDebug", "Row has " + row.childElementCount + " children.");
		
			if (row.childElementCount > 1){
				var header = row.children[0];
				var value = row.children[1];
		
				if (header.innerText != null){
					window.chrome.webview.hostObjects.sync.atlasAddon.ExecuteAddonFunction("LogDebug", "Header Text: " + header.innerText);
				}
		
				if (value.innerText != null){
					window.chrome.webview.hostObjects.sync.atlasAddon.ExecuteAddonFunction("LogDebug", "Value Text: " + value.innerText);
				}
		
				if (header.innerText.toLowerCase() == "call number:"){
					window.chrome.webview.hostObjects.sync.atlasAddon.ExecuteAddonFunction("SetFieldValue", "Transaction", "CallNumber", value.innerText);
				}
				else if (header.innerText.toLowerCase() == "location:"){
					window.chrome.webview.hostObjects.sync.atlasAddon.ExecuteAddonFunction("SetFieldValue", "Transaction", "Location", value.innerText);
				}
			}
		}
	]];

	opacForm.Browser:ExecuteScript(importInfoClassicScript);

	ExecuteCommand("SwitchTab", {"Detail"});
end

function CheckHoldingsPageLoaded()
	local checkHoldingsPageLoadedScript = [[
		(function(){
			window.chrome.webview.hostObjects.sync.atlasAddon.ExecuteAddonFunction("LogDebug", "Checking if Holdings Page is loaded.");

			var holdingsList = document.getElementsByTagName("ul");

			window.chrome.webview.hostObjects.sync.atlasAddon.ExecuteAddonFunction("LogDebug", "Found " + holdingsList.length + " ULs.");

			for (let row of holdingsList){
				if (row.getAttribute("title") == "Bibliographic Record Display"){
					return "True";
				}
			}
			return "False";
		})()
	]];

	return opacForm.Browser:EvaluateScript(checkHoldingsPageLoadedScript).Result == "True";
end

function HoldingsPageLoaded()
	InjectImportButtons();
	opacForm.Browser:RegisterPageHandler("custom", "CheckHoldingsPageLoaded", "HoldingsPageLoaded", false);
end

function ImportHolding(location, callNumber)
	SetFieldValue("Transaction", "Location", location);
	SetFieldValue("Transaction", "CallNumber", callNumber);

	ExecuteCommand("SwitchTab", {"Detail"});
end

function InjectImportButtons()
	local injectImportButtonsScript = [[
		(function (locationLabelClass, callNumberLabelClass) {
			var displayHoldingsList = document.getElementsByClassName("displayHoldings");
		
			for (let holdingsRow of displayHoldingsList){
				var divList = holdingsRow.children;
		
				for (let row of divList){
					var rowClass = row.getAttribute("class");
		
					if (rowClass == "oddHoldingsRow" || rowClass == "evenHoldingsRow"){
						// Make sure we haven't already injected our import button into the div.
						// This can happen as a result of the page handler being called more than once.
						var alreadyInjected = false;
		
						var inputList = row.getElementsByTagName("INPUT");
		
						for (let button of inputList){
							if (button.getAttribute("title") == "atlas-import"){
								alreadyInjected = true;
								break;
							}
						}
		
						if (alreadyInjected == false){
							var liElement = document.createElement("li");
							liElement.setAttribute("class", "bibTag");
		
							var inputElement = document.createElement("INPUT");
							inputElement.setAttribute("title", "atlas-import");
							inputElement.setAttribute("type", "button");
							inputElement.setAttribute("value", "Import");
		
							row.insertAdjacentElement("beforeend", liElement);
							liElement.appendChild(inputElement);
		
							let location = "";
							let callNumber = "";
		
							var spanList = row.getElementsByTagName("span");
		
							for (let i = 0; i < spanList.length; i++){
								var spanClass = spanList[i].getAttribute("class");
		
								// The span with the value always comes after the label.
								if (spanClass == locationLabelClass && spanList[i].innerText == "Location:"){
									
									// Because the span containing the location has nested divs that also contain text, this is necesssary
									// to extract only the location text.
									location = [].reduce.call(spanList[i+1].childNodes, function(result, childNode) { return result + (childNode.nodeType === 3 ? childNode.textContent : ''); }, '');
								}
		
								if (spanClass == callNumberLabelClass && spanList[i].innerText == "Call Number:"){
									callNumber = spanList[i+1].innerText;
								}
								
								if (location != "" && callNumber != ""){
									break;
								}
								
							}

							inputElement.onclick = function(){ window.chrome.webview.hostObjects.sync.atlasAddon.ExecuteAddonFunction("ImportHolding", location, callNumber)} ;
						}
					}
				}
			}
		})
	]];

	opacForm.Browser:ExecuteScript(injectImportButtonsScript, {settings.LocationLabelClass, settings.CallNumberLabelClass});
end