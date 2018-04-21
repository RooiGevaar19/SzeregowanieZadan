program ProjectMain;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Classes, UnitTask, SysUtils;

var
	db   : TaskDB;
	maxl : LongInt;

begin
	db := loadDBFromFile(ParamStr(1));
	printDBContent(db);
	maxl := applyCPM(db);
	writeln(maxl);
	printDBContent(db);
	//buildSchedule(db, maxl);
	dropDB(db);
end.

