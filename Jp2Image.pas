unit Jp2Image;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Description:	Reader for JPEG2000 images                                    //
// Version:	0.2                                                           //
// Date:	03-MAR-2025                                                   //
// License:     MIT                                                           //
// Target:	Win64, Free Pascal, Delphi                                    //
// Copyright:	(c) 2025 Xelitan.com.                                         //
//		All rights reserved.                                          //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

interface

uses Classes, Graphics, SysUtils, Math, Types, Dialogs;

const
  LIBJP2 = 'libjasper.dll';

type
  jas_image_coord_t = Integer;
  jas_image_cmpttype_t = Integer;
  jas_clrspc_t = Cardinal;

  jas_stream_t = record end;
  Pjas_stream_t = ^jas_stream_t;

  jas_cmprof_t = record end;
  Pjas_cmprof_t = ^jas_cmprof_t;

  jas_image_cmpt_t = record
     tlx_: jas_image_coord_t;        // X-coord of top-left corner
     tly_: jas_image_coord_t;        // Y-coord of top-left corner
     hstep_: jas_image_coord_t;      // Horizontal sampling period
     vstep_: jas_image_coord_t;      // Vertical sampling period
     width_: jas_image_coord_t;      // Component width in samples
     height_: jas_image_coord_t;     // Component height in samples
     prec_: Cardinal;                // Precision (bits per sample)
     sgnd_: Integer;                 // Signedness (0=unsigned, 1=signed)
     stream_: Pjas_stream_t;         // Pointer to stream with component data
     cps_: Cardinal;                 // Characters per sample in stream
     type_: jas_image_cmpttype_t;    // Component type (e.g., color channel)
   end;
   Pjas_image_cmpt_t = ^jas_image_cmpt_t;

  jas_image_t = record
    tlx_: Integer;      // Top-left x of image
    tly_: Integer;      // Top-left y of image
    brx_: Integer;      // Bottom-right x
    bry_: Integer;      // Bottom-right y
    numcmpts_: Integer; // Number of components
    maxcmpts_: Integer; // Maximum components
    cmpts_: Pjas_image_cmpt_t;  // Array of components
    clrspc_: jas_clrspc_t;
    cmprof_: pjas_cmprof_t;
  end;
  pjas_image_t = ^jas_image_t;
  jas_logtype_t = Cardinal;
  Tjas_vlogmsgf_func = function(typ: jas_logtype_t; const fmt: PAnsiChar; ap: array of const): Integer; cdecl;

  function jas_init: Integer; cdecl; external 'LibJasper.dll';
  procedure jas_cleanup; cdecl; external 'LibJasper.dll';
  function jas_stream_fopen(filename: PAnsiChar; mode: PAnsiChar): pjas_stream_t; cdecl; external 'LibJasper.dll';
  function jas_stream_memopen(buffer: PByte; buffer_size: Integer): pjas_stream_t; cdecl; external 'LibJasper.dll';
  function jas_image_decode(stream: pjas_stream_t; fmt: Integer; opts: PAnsiChar): Pjas_image_t; cdecl; external 'LibJasper.dll';
  procedure jas_stream_close(stream: pjas_stream_t); cdecl; external 'LibJasper.dll';
  procedure jas_image_destroy(image: pjas_image_t); cdecl; external 'LibJasper.dll';
  function jas_image_cmptprec(image: pjas_image_t; cmptno: Integer): Integer; cdecl; external 'LibJasper.dll';
  function jas_image_cmptsgnd(image: pjas_image_t; cmptno: Integer): Integer; cdecl; external 'LibJasper.dll';
  function jas_image_readcmptsample(image: pjas_image_t; cmptno: Integer; x, y: Integer): Integer; cdecl; external 'LibJasper.dll';

  procedure jas_conf_clear(); cdecl; external 'LibJasper.dll';
  function jas_init_library(): Integer; cdecl; external 'LibJasper.dll';
  procedure jas_conf_set_debug_level(debug_level: Integer); cdecl; external 'LibJasper.dll';
  procedure jas_conf_set_max_mem_usage(max_mem: Cardinal); cdecl; external 'LibJasper.dll';
  function jas_cleanup_library(): Integer; cdecl; external 'LibJasper.dll';
  function jas_init_thread(): Integer; cdecl; external 'LibJasper.dll';
  function jas_cleanup_thread(): Integer; cdecl; external 'LibJasper.dll';
  procedure jas_conf_set_vlogmsgf(func: Tjas_vlogmsgf_func); cdecl; external 'LibJasper.dll';
  function jas_vlogmsgf_discard(typ: jas_logtype_t; const fmt: PAnsiChar; ap: array of const): Integer; cdecl; external 'LibJasper.dll';

  { TJp2Image }
type
  TJp2Image = class(TGraphic)
  private
    FBmp: TBitmap;
    FCompression: Integer;
    procedure DecodeFromStream(Str: TStream);
    procedure EncodeToStream(Str: TStream);
  protected
    procedure Draw(ACanvas: TCanvas; const Rect: TRect); override;
  //    function GetEmpty: Boolean; virtual; abstract;
    function GetHeight: Integer; override;
    function GetTransparent: Boolean; override;
    function GetWidth: Integer; override;
    procedure SetHeight(Value: Integer); override;
    procedure SetTransparent(Value: Boolean); override;
    procedure SetWidth(Value: Integer);override;
  public
    procedure SetLossyCompression(Value: Cardinal);
    procedure Assign(Source: TPersistent); override;
    procedure LoadFromStream(Stream: TStream); override;
    procedure SaveToStream(Stream: TStream); override;
    constructor Create; override;
    destructor Destroy; override;
    function ToBitmap: TBitmap;
  end;

implementation

{ TJp2Image }

procedure TJp2Image.DecodeFromStream(Str: TStream);
var Stream: pjas_stream_t;
    Image: Pjas_image_t;
    NumComponents: Integer;
    x, y: Integer;
    r, g, b, a: Integer;
    AWidth, AHeight: Integer;
    P: PByteArray;
    Buff: array of Byte;
    BufSize: Integer;
begin
  jas_conf_clear();
  jas_conf_set_max_mem_usage(2*1024*1024*1024);
  //jas_conf_set_debug_level(2);
  jas_conf_set_vlogmsgf(jas_vlogmsgf_discard);
  if jas_init_library() <> 0 then raise Exception.Create('Failed');
  jas_init_thread();

  try
    BufSize := Str.Size - Str.Position;
    SetLength(Buff, BufSize);
    Str.Read(Buff[0], BufSize);
    stream := jas_stream_memopen(@Buff[0], BufSize);

    if not Assigned(Stream) then Exit;

    try
      Image := jas_image_decode(Stream, -1, nil);
      if not Assigned(Image) then Exit;

      try
        AWidth  := image^.brx_ - image^.tlx_;
        AHeight := image^.bry_ - image^.tly_;

        NumComponents := Image^.numcmpts_;
        FBmp.SetSize(AWidth, AHeight);

        if NumComponents = 1 then begin
          for y:=0 to AHeight-1 do begin
              P := FBmp.Scanline[y];

              for x:=0 to AWidth-1 do begin
                g := jas_image_readcmptsample(Image, 0, x, y);

                P[4*x  ] := g;
                P[4*x+1] := g;
                P[4*x+2] := g;
                P[4*x+3] := 255;
              end;
            end;
        end
        else if NumComponents = 3 then begin
          for y:=0 to AHeight-1 do begin
            P := FBmp.Scanline[y];

            for x:=0 to AWidth-1 do begin
              r := jas_image_readcmptsample(Image, 0, x, y);
              g := jas_image_readcmptsample(Image, 1, x, y);
              b := jas_image_readcmptsample(Image, 2, x, y);

              P[4*x  ] := b;
              P[4*x+1] := g;
              P[4*x+2] := r;
              P[4*x+3] := 255;
            end;
          end;
        end
        else if NumComponents  = 4 then begin
          for y:=0 to AHeight-1 do begin
            P := FBmp.Scanline[y];

            for x:=0 to AWidth-1 do begin
              r := jas_image_readcmptsample(Image, 0, x, y);
              g := jas_image_readcmptsample(Image, 1, x, y);
              b := jas_image_readcmptsample(Image, 2, x, y);
              a := jas_image_readcmptsample(Image, 3, x, y);

              P[4*x  ] := b;
              P[4*x+1] := g;
              P[4*x+2] := r;
              P[4*x+3] := a;
            end;
          end;
        end;
      finally
        jas_image_destroy(Image);
      end;
    finally
      jas_stream_close(Stream);
    end;
  finally
    jas_cleanup_thread;
    jas_cleanup_library;
  end;
end;

procedure TJp2Image.EncodeToStream(Str: TStream);
begin
  //
end;

procedure TJp2Image.Draw(ACanvas: TCanvas; const Rect: TRect);
begin
  ACanvas.StretchDraw(Rect, FBmp);
end;

function TJp2Image.GetHeight: Integer;
begin
  Result := FBmp.Height;
end;

function TJp2Image.GetTransparent: Boolean;
begin
  Result := False;
end;

function TJp2Image.GetWidth: Integer;
begin
  Result := FBmp.Width;
end;

procedure TJp2Image.SetHeight(Value: Integer);
begin
  FBmp.Height := Value;
end;

procedure TJp2Image.SetTransparent(Value: Boolean);
begin
  //
end;

procedure TJp2Image.SetWidth(Value: Integer);
begin
  FBmp.Width := Value;
end;

procedure TJp2Image.SetLossyCompression(Value: Cardinal);
begin
  FCompression := Value;
end;

procedure TJp2Image.Assign(Source: TPersistent);
var Src: TGraphic;
begin
  if source is tgraphic then begin
    Src := Source as TGraphic;
    FBmp.SetSize(Src.Width, Src.Height);
    FBmp.Canvas.Draw(0,0, Src);
  end;
end;

procedure TJp2Image.LoadFromStream(Stream: TStream);
begin
  DecodeFromStream(Stream);
end;

procedure TJp2Image.SaveToStream(Stream: TStream);
begin
  EncodeToStream(Stream);
end;

constructor TJp2Image.Create;
begin
  inherited Create;

  FBmp := TBitmap.Create;
  FBmp.PixelFormat := pf32bit;
  FBmp.SetSize(1,1);
  FCompression := 90;
end;

destructor TJp2Image.Destroy;
begin
  FBmp.Free;
  inherited Destroy;
end;

function TJp2Image.ToBitmap: TBitmap;
begin
  Result := FBmp;
end;

initialization
  TPicture.RegisterFileFormat('jp2','Jp2 Image', TJp2Image);

finalization
  TPicture.UnregisterGraphicClass(TJp2Image);

end.
