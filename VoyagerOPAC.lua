local settings = {}
settings.OpacUrl = GetSetting("OPACURL");
settings.Tomcat =  GetSetting("TomcatWebvoyage");
settings.LocationLabelClass =  GetSetting("TomcatLocationLabelSpanClass");
settings.LocationValueClass =  GetSetting("TomcatLocationValueSpanClass");
settings.CallNumberLabelClass =  GetSetting("TomcatCallNumberLabelSpanClass");
settings.CallNumberValueClass =  GetSetting("TomcatCallNumberValueSpanClass");

local interfaceMngr = nil;
local opacForm = {};
opacForm.Form = nil;
opacForm.RibbonPage = nil;
opacForm.Browser = nil;

local searchTerm = nil;
local searchCode = nil;
local searchBox = "querybox";

--[[
	When inserting a new HtmlElement into an existing HtmlElement, the method InsertAdjacentElement() requires a parameter of type HtmlElementInsertionOrientation.
	HtmlElementInsertionOrientation is a .NET enumeration that does not correspond to any of Lua's basic data types, so we are importing it using Lua's assembly
	import functionality.  Once we have a reference to the type from luanet.import_type, we will store it in a table named 'types' so that we can easily refer to
	it when inserting the new HtmlElement.
--]]
local types = {};
luanet.load_assembly("System.Windows.Forms");
types["System.Windows.Forms.HtmlElementInsertionOrientation"] = luanet.import_type("System.Windows.Forms.HtmlElementInsertionOrientation");

function Init()
    interfaceMngr = GetInterfaceManager();
    
	-- Create a form
	opacForm.Form = interfaceMngr:CreateForm("OPAC Search", "Script");
	
	-- Add a browser
	opacForm.Browser = opacForm.Form:CreateBrowser("OPAC Search", "OPAC Search Browser", "OPAC Search");
	
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
		searchCode = "GKEY^";		
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
	if settings.Tomcat == false then
		opacForm.Browser:SetFormValue(searchBox, "search_arg", searchTerm);
		opacForm.Browser:SetFormValue(searchBox, "search_code", searchCode);		
	else
		opacForm.Browser:SetFormValue(searchBox, "searchArg", searchTerm);
		opacForm.Browser:SetFormValue(searchBox, "searchCode", searchCode);		
		opacForm.Browser:RegisterPageHandler("custom", "CheckHoldingsPageLoaded", "HoldingsPageLoaded", false);		
	end
	opacForm.Browser:SubmitForm(searchBox);	
end

function ImportInfo()
	if settings.Tomcat == false then
		ImportInfoClassic();
	end
end

function ImportInfoClassic()
	local obrowser = opacForm.Browser.WebBrowser;	
	local document = obrowser.Document;
	local detailsTable = opacForm.Browser:GetElementByCollectionIndex(document:GetElementsByTagName("Table"), 1);
	
	local detailRows = detailsTable:GetElementsByTagName("TR");
	
	LogDebug("Found " .. detailRows.Count .. " rows.");
	
	for i =0, detailRows.Count - 1 do
		local row = opacForm.Browser:GetElementByCollectionIndex(detailRows, i);
		
		LogDebug("Row has " .. row.Children.Count .. " children.");
		
		if row.Children.Count > 1 then
			
			local header = opacForm.Browser:GetElementByCollectionIndex(row.Children, 0);
			local value = opacForm.Browser:GetElementByCollectionIndex(row.Children, 1);
			
			if header.InnerText ~= nil then
				LogDebug("Header Text: " .. header.InnerText);
			end
			
			if value.InnerText ~= nil then
				LogDebug("Value Text: " .. value.InnerText);
			end
			
			if header.InnerText == "Call number:" then
				SetFieldValue("Transaction", "CallNumber", value.InnerText);
			elseif header.InnerText == "Location:" then
				SetFieldValue("Transaction", "Location", value.InnerText);
			end
		end
		
		i = i + 1;
	end
	
	ExecuteCommand("SwitchTab", {"Detail"});
end

function CheckHoldingsPageLoaded()
	LogDebug("Checking if Holdings Page is loaded");
	
	local obrowser = opacForm.Browser.WebBrowser;	
	local document = obrowser.Document;
	
	local holdingsList = document:GetElementsByTagName('ul');
	
	LogDebug("Found " .. holdingsList.Count .. " ULs.");
	
	local holdingsEnumerator = holdingsList:GetEnumerator();
	while holdingsEnumerator:MoveNext() do
		local row = holdingsEnumerator.Current;
		local ulTitle = row:GetAttribute("title");

		if ulTitle == "Bibliographic Record Display" then			
			return true;								
		end
	end
	
	return false;
end
			
function HoldingsPageLoaded()	
	InjectImportButtons();	
	opacForm.Browser:RegisterPageHandler("custom", "CheckHoldingsPageLoaded", "HoldingsPageLoaded", false);		
end

function ImportHolding(row)	
	local liList = row:GetElementsByTagName('li');
	LogDebug("Found " .. liList.Count .. " holdings record LIs.");
	
	local liEnumerator = liList:GetEnumerator();
	while liEnumerator:MoveNext() do
		local liRow = liEnumerator.Current;
		local liClass = liRow:GetAttribute("className");			
		
		if string.match(liClass:upper(), "BIBTAG") == "BIBTAG" then
			local spanList = liRow:GetElementsByTagName('span');
			LogDebug("Found " .. spanList.Count .. " bibTag spans.");
			
			local lastSpanText = "";
			local spanEnumerator = spanList:GetEnumerator();
			while spanEnumerator:MoveNext() do
				spanRow = spanEnumerator.current;
				local spanClass = spanRow:GetAttribute("className");						
				
				LogDebug("Last Span Text: " .. lastSpanText);
				LogDebug("Current Span Class: " .. spanClass);
				LogDebug("Current Span Text: " .. spanRow.InnerText);
				
				if spanClass == settings.LocationValueClass and lastSpanText == "Location:" then						
					SetFieldValue("Transaction", "Location", spanRow.InnerText);
				end;
				
				if spanClass == settings.CallNumberValueClass and lastSpanText == "Call Number:" then						
					SetFieldValue("Transaction", "CallNumber", spanRow.InnerText);
				end;
				
				if (spanClass == settings.LocationLabelClass) or (spanClass == settings.CallNumberLabelClass)  then						
					lastSpanText = spanRow.InnerText;
				else 
					lastSpanText = "";
				end;				
			end					
		end						
	end
	
	ExecuteCommand("SwitchTab", {"Detail"});
end

function InjectImportButtons()
	local obrowser = opacForm.Browser.WebBrowser;	
	local document = obrowser.Document;
	
	local holdingsList = document:GetElementsByTagName('div');
	
	LogDebug("Found " .. holdingsList.Count .. " ULs.");
	
	local holdingsEnumerator = holdingsList:GetEnumerator();
	while holdingsEnumerator:MoveNext() do
		local hRow = holdingsEnumerator.Current;
		local rowClass = hRow:GetAttribute("className");			
		
		if rowClass == "displayHoldings" then
			local divList = hRow.Children;
			
			local divEnumerator = divList:GetEnumerator();
			while divEnumerator:MoveNext() do
				local row = divEnumerator.Current;
				rowClass = row:GetAttribute("className");			
								
				if rowClass == "oddHoldingsRow" or rowClass == "evenHoldingsRow" then		
					local alreadyInjected = false;
					
					--Make sure we have not already injected our import button into the div
					--This can happen as a result of the page handler being called upon more than once
					local inputList = row:GetElementsByTagName("INPUT");	
					local inputEnumerator = inputList:GetEnumerator();
					while inputEnumerator:MoveNext() do
						local button = inputEnumerator.Current;				
						local buttonClass = button:GetAttribute("title");												
						if buttonClass == "atlas-import" then		
							alreadyInjected = true;
							break;
						end
					end
					
					if alreadyInjected == false then
						local liElement = document:CreateElement("li");		
						liElement:SetAttribute("className", "bibTag");
						
						local inputElement = document:CreateElement("INPUT");
						inputElement:SetAttribute("title", "atlas-import");
						inputElement:SetAttribute("type", "button");
						inputElement:SetAttribute("value", "Import");

						row:InsertAdjacentElement(types["System.Windows.Forms.HtmlElementInsertionOrientation"].BeforeEnd, liElement);
						liElement:AppendChild(inputElement);
						
						inputElement:add_Click(function(a) ImportHolding(row) end);	
					end
				end										
			end		
		end
	end
end	
	
	
