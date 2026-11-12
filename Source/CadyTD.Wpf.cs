using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Media.Media3D;
using System.Windows.Data;
using System.Windows.Markup;
using System.Windows.Threading;
using System.Media;

namespace CadyTowerDefense
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            RenderOptions.ProcessRenderMode = System.Windows.Interop.RenderMode.Default;
            Application app = new Application();
            app.ShutdownMode = ShutdownMode.OnMainWindowClose;
            app.Run(new MainWindow());
        }
    }

    internal sealed class HeroType
    {
        public string Id, Name, Icon, Description, Special, Sprite;
        public int Price, Damage;
        public double Range, Rate;
        public int[] UpgradeCosts;
        public string[] Forms;
    }
    internal sealed class Tower
    {
        public HeroType Type;
        public double X, Y, Range, Damage, Rate, Cooldown, Power=.30, LastShot=-20, LastTargetX, LastTargetY;
        public int Level, Invested;
        public string Aura="speed";
        public TowerModel3D Model;
    }
    internal sealed class TowerModel3D
    {
        public ModelVisual3D Visual;
        public ScaleTransform3D ScaleTransform,LeftEyeScale,RightEyeScale;
        public TranslateTransform3D PositionTransform;
        public AxisAngleRotation3D Yaw,Torso,Head,LeftShoulder,RightShoulder,LeftElbow,RightElbow,LeftHip,RightHip,AuraRotation,CapeRotation;
        public double HeightNorm=2.36,Phase;
        public string TypeId;
        public int Level;
    }
    internal sealed class AmbientCritterRig3D
    {
        public ModelVisual3D Visual;
        public TranslateTransform3D WorldPosition,CreaturePosition;
        public ScaleTransform3D WorldScale,CreatureScale;
        public AxisAngleRotation3D CreatureYaw,FrontLeft,FrontRight,BackLeft,BackRight,Tail;
        public double X,Y,Range,Phase,Scale;
    }
    internal sealed class BirdRig3D
    {
        public ModelVisual3D Visual;
        public TranslateTransform3D Position;
        public ScaleTransform3D Scale;
        public AxisAngleRotation3D Yaw,LeftWing,RightWing;
        public double X,Y,Range,Height,Phase,Speed;
    }
    internal sealed class Enemy
    {
        public string Kind, Name;
        public double Distance, X, Y, Speed, Hp, MaxHp, Radius, Slow=1, SlowUntil, Phase;
        public int Reward, PathSegment;
        public bool Boss;
        public EnemyRig3D Model;
    }
    internal sealed class EnemyRig3D
    {
        public ModelVisual3D Visual;
        public AxisAngleRotation3D Yaw, LeftHip, RightHip, LeftKnee, RightKnee, LeftShoulder, RightShoulder, LeftElbow, RightElbow, Torso, Head, WargFrontLeft, WargFrontRight, WargBackLeft, WargBackRight;
        public ScaleTransform3D ScaleTransform;
        public TranslateTransform3D PositionTransform;
        public bool Quadruped;
        public double HeightNorm=2.2,Scale=1;
    }
    internal sealed class Bolt
    {
        public Tower Source;
        public Enemy Target;
        public double X, Y, Damage, Speed, Slow=1, SlowTime, Splash, Freeze, Phase;
        public string Type;
        public HashSet<Enemy> Hit=new HashSet<Enemy>();
        public int Pierce;
        public BoltModel3D Model;
    }
    internal sealed class BoltModel3D
    {
        public ModelVisual3D Visual;
        public ScaleTransform3D ScaleTransform;
        public TranslateTransform3D PositionTransform;
        public AxisAngleRotation3D Yaw,Spin;
        public string TypeId;
    }
    internal sealed class Burst
    {
        public double X, Y, Life, Duration;
        public Color Color;
    }
    internal sealed class SoundVoice : IDisposable
    {
        public string Alias;
        public int CutoffMs;
        public void Dispose(){if(!String.IsNullOrEmpty(Alias)){AudioManager.SendCommand("stop "+Alias);AudioManager.SendCommand("close "+Alias);Alias=null;}}
    }

    internal sealed class AudioManager : IDisposable
    {
        [DllImport("winmm.dll",CharSet=CharSet.Auto)] private static extern int mciSendString(string command,StringBuilder result,int length,IntPtr callback);
        private const string MusicAlias="cady_music";
        private readonly Dictionary<string,SoundVoice[]> pools=new Dictionary<string,SoundVoice[]>();
        private readonly Dictionary<string,int> next=new Dictionary<string,int>();
        private bool musicOpen;
        private int effectPosition=350;
        private static int Send(string s){return mciSendString(s,null,0,IntPtr.Zero);}
        internal static void SendCommand(string s){Send(s);}
        public AudioManager(string root)
        {
            string music=Path.Combine(root,"Assets","Music","Everlasting-Shine.mp3");
            if(File.Exists(music))musicOpen=Send("open \""+music+"\" type mpegvideo alias "+MusicAlias)==0;
            AddSource(root,"gondor","asta-slash",420);AddSource(root,"elf","yuno-wind",900);AddSource(root,"dwarf","magna-fire",780);AddSource(root,"aura","vanessa-thread",420);AddSource(root,"ice","noelle-ice",600);
            AddSource(root,"deathgoblin","death-goblin",1250);AddSource(root,"deathorc","death-orc",650);AddSource(root,"deathuruk","death-uruk",620);AddSource(root,"deathwarg","death-warg",820);AddSource(root,"deathtroll","death-troll",1250);AddSource(root,"deathnazgul","death-nazgul",1350);
            SetEffectVolume(effectPosition);
        }
        private void AddSource(string root,string key,string file,int cutoffMs)
        {
            string path=Path.Combine(root,"Assets","Sfx",file+".mp3");if(!File.Exists(path))return;SoundVoice[] group=new SoundVoice[3];for(int i=0;i<group.Length;i++){string alias="cadyfx"+key+i;if(Send("open \""+path+"\" type mpegvideo alias "+alias)!=0)continue;Send("set "+alias+" time format milliseconds");group[i]=new SoundVoice{Alias=alias,CutoffMs=cutoffMs};}pools[key]=group;next[key]=0;
        }
        public void PlayMusic(int volume){SetMusicVolume(volume);if(musicOpen)Send("play "+MusicAlias+" repeat");}
        public void StopMusic(){if(musicOpen)Send("stop "+MusicAlias);}
        public void SetMusicVolume(int value){if(musicOpen)Send("setaudio "+MusicAlias+" volume to "+Math.Max(0,Math.Min(100,value))*10);}
        public void SetEffectVolume(double value)
        {
            effectPosition=(int)Math.Max(0,Math.Min(1000,value));double x=effectPosition/1000.0;int volume=(int)Math.Round(Math.Pow(x,4.0)*1000);foreach(SoundVoice[] group in pools.Values)foreach(SoundVoice voice in group)if(voice!=null&&!String.IsNullOrEmpty(voice.Alias))Send("setaudio "+voice.Alias+" volume to "+volume);
        }
        private void Play(string key){SoundVoice[] p;if(effectPosition<=0||!pools.TryGetValue(key,out p))return;for(int tries=0;tries<p.Length;tries++){int i=next[key]++%p.Length;SoundVoice v=p[i];if(v==null||String.IsNullOrEmpty(v.Alias))continue;Send("stop "+v.Alias);Send("play "+v.Alias+" from 0 to "+v.CutoffMs);return;}}
        public void PlayTower(string id){Play(id);}
        public void PlayDeath(string kind){string key="death"+kind;if(!pools.ContainsKey(key))key="deathorc";Play(key);}
        public void Dispose(){StopMusic();if(musicOpen)Send("close "+MusicAlias);foreach(SoundVoice[] group in pools.Values)foreach(SoundVoice v in group)if(v!=null)v.Dispose();pools.Clear();}
    }

    internal sealed class GameSurface : FrameworkElement
    {
        private readonly MainWindow game;
        public GameSurface(MainWindow owner){game=owner;Focusable=true;ClipToBounds=true;SnapsToDevicePixels=true;RenderOptions.SetBitmapScalingMode(this,BitmapScalingMode.HighQuality);}
        protected override void OnRender(DrawingContext dc){base.OnRender(dc);dc.DrawRectangle(Brushes.Transparent,null,new Rect(0,0,ActualWidth,ActualHeight));game.RenderField(dc,ActualWidth,ActualHeight);}
        protected override void OnMouseMove(MouseEventArgs e){base.OnMouseMove(e);game.UpdatePointer(ToWorld(e.GetPosition(this),ActualWidth,ActualHeight));}
        protected override void OnMouseLeave(MouseEventArgs e){base.OnMouseLeave(e);game.PointerExit();}
        protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e){base.OnMouseLeftButtonDown(e);Focus();game.HandleFieldClick(ToWorld(e.GetPosition(this),ActualWidth,ActualHeight));e.Handled=true;}
        protected override void OnMouseRightButtonDown(MouseButtonEventArgs e){base.OnMouseRightButtonDown(e);Focus();game.HandleFieldRightClick();e.Handled=true;}
        protected override void OnMouseWheel(MouseWheelEventArgs e){base.OnMouseWheel(e);game.ZoomBy(e.Delta,e.GetPosition(this),ActualWidth,ActualHeight);e.Handled=true;}
        private Point ToWorld(Point p,double w,double h){return game.ScreenToWorld(p,w,h);}
    }

    internal sealed class MainWindow : Window
    {
        public const double BaseWorldW=2560,BaseWorldH=1600;
        public const int ArenaCount=18,WavesPerArena=15;
        public double WorldW=BaseWorldW,WorldH=BaseWorldH,MapScale=1.0,Zoom=1.0;
        private readonly string root=AppDomain.CurrentDomain.BaseDirectory;
        private readonly List<HeroType> types=new List<HeroType>();
        private readonly List<Tower> towers=new List<Tower>();
        private readonly List<Enemy> enemies=new List<Enemy>();
        private readonly Dictionary<string,Queue<EnemyRig3D>> enemyModelPool=new Dictionary<string,Queue<EnemyRig3D>>();
        private readonly Random gameplayRandom=new Random();
        private readonly List<Bolt> bolts=new List<Bolt>();
        private readonly List<Burst> bursts=new List<Burst>();
        private readonly List<AmbientCritterRig3D> ambientCritters=new List<AmbientCritterRig3D>();
        private readonly List<BirdRig3D> birds=new List<BirdRig3D>();
        private readonly string[] arenaShort={"Лес","Пепел","Север","Итилиэн","Мория","Рохан","Лотлориэн","Эребор","Мордор","Гондор","Туманные горы","Западный край","Дол Гулдур","Ангмар","Кхазад-дум","Лихолесье","Пелленор","Удун"};
        private readonly string[] enemyNames={"Гоблин-разведчик","Орк Мордора","Урук-хай","Всадник на варге","Боевой тролль","Назгул"};
        private readonly string[] enemyIds={"goblin","orc","uruk","warg","troll","nazgul"};
        private readonly AudioManager audio;
        private readonly Stopwatch frameClock=Stopwatch.StartNew();
        private static readonly Dictionary<Color,SolidColorBrush> brushCache=new Dictionary<Color,SolidColorBrush>();
        private static readonly Dictionary<Color,Dictionary<int,Pen>> penCache=new Dictionary<Color,Dictionary<int,Pen>>();
        private static readonly Dictionary<Color,Material> material3DCache=new Dictionary<Color,Material>();
        private static readonly Dictionary<Color,Material> emissive3DCache=new Dictionary<Color,Material>();
        private static readonly Material[] rockTextureCache=new Material[3];
        private static Brush stoneTextureBrush;
        private static MeshGeometry3D unitSphereMesh;
        private readonly Brush gold=Frozen(Color.FromRgb(234,197,116)), ivory=Frozen(Color.FromRgb(239,230,205)), muted=Frozen(Color.FromRgb(173,177,172));
        private readonly Brush panelDark=Frozen(Color.FromRgb(19,25,31));
        private GameSurface surface;
        private Viewport3D worldView;
        private OrthographicCamera worldCamera;
        private ModelVisual3D groundVisual,lightVisual;
        private ModelVisual3D buildGhostVisual;
        private ScaleTransform3D buildGhostScale;
        private TranslateTransform3D buildGhostPosition;
        private string buildGhostType;
        private int groundScene=-1;
        private double groundDepthScale=1,cameraViewWidth=-1,cameraViewHeight=-1,cameraWorldW=-1,cameraWorldH=-1,cameraCenterX=-1,cameraCenterY=-1,viewCenterX=BaseWorldW*.5,viewCenterY=BaseWorldH*.5;
        private double targetZoom=1,targetCenterX=BaseWorldW*.5,targetCenterY=BaseWorldH*.5;
        private BitmapSource sceneCache;
        private int sceneCacheArena=-1;
        private Geometry routeGeometry;
        private Point[] path=new Point[0],motionPath=new Point[0];
        private double[] motionDistances=new double[0];
        private double routeLength,clock,lastFrame,lastRender;
        private double worldScale=1,offsetX,offsetY,gameSpeed=1,spawnCountdown;
        private Point mouseWorld=new Point(-100,-100);
        private HeroType selectedType;
        private Tower selectedTower;
        private TextBlock goldValue,waveValue,livesValue,arenaValue,statusText,selectionText,overlayHeading,overlayBody;
        private Button startButton,pauseButton,musicButton,upgradeButton,sellButton,auraSpeedButton,auraDamageButton;
        private Button speedButton;
        private TextBlock zoomLabel;
        private Popup speedPopup;
        private Slider magicSlider,musicSlider;
        private DispatcherTimer effectVolumeDelay;
        private DispatcherTimer enemyPrewarmTimer;
        private int enemyPrewarmIndex;
        private double pendingEffectVolume=350;
        private StackPanel cardsPanel;
        private readonly Dictionary<string,Button> cardButtons=new Dictionary<string,Button>();
        private Border overlayBorder,pauseBorder;
        private int arenaIndex,waveInArena,totalWaves,goldCount=360,lives=15,remainingSpawns;
        private bool waveRunning,stageReady,gameOver,musicOn,paused;
        private bool fullScreen;
        private readonly Color[] towerColors={Color.FromRgb(198,101,71),Color.FromRgb(111,188,139),Color.FromRgb(241,154,68),Color.FromRgb(207,104,146),Color.FromRgb(123,190,225)};

        public MainWindow()
        {
            Title="Кади · Рубеж Средиземья";Icon=LoadSprite(Path.Combine(root,"Assets","Icons","black-bulls-emblem.png"),128);Width=1500;Height=900;MinWidth=1180;MinHeight=740;WindowState=WindowState.Maximized;Background=new SolidColorBrush(Color.FromRgb(13,18,21));Foreground=ivory;FontFamily=new FontFamily("Segoe UI");FontSize=13;UseLayoutRounding=true;SnapsToDevicePixels=true;
            BuildTypes();audio=new AudioManager(root);SetArenaPath();BuildUi();RefreshHud();RefreshCards();UpdateSelection();
            Loaded+=delegate{musicOn=true;musicButton.Content="♫  Музыка: вкл";audio.PlayMusic((int)musicSlider.Value);CompositionTarget.Rendering+=OnFrame;lastFrame=frameClock.Elapsed.TotalSeconds;StartEnemyModelPrewarm();};
            Closed+=delegate{CompositionTarget.Rendering-=OnFrame;if(effectVolumeDelay!=null)effectVolumeDelay.Stop();if(enemyPrewarmTimer!=null)enemyPrewarmTimer.Stop();audio.Dispose();};
            KeyDown+=OnKeyDown;PreviewKeyDown+=delegate(object sender,KeyEventArgs e){if(e.Key==Key.Space){e.Handled=true;if(paused)TogglePause();else StartWave();}};
        }
        private static SolidColorBrush Frozen(Color c){SolidColorBrush b;if(!brushCache.TryGetValue(c,out b)){b=new SolidColorBrush(c);b.Freeze();brushCache[c]=b;}return b;}
        private static Pen Stroke(Color color,double thickness){Dictionary<int,Pen> group;if(!penCache.TryGetValue(color,out group)){group=new Dictionary<int,Pen>();penCache[color]=group;}int key=(int)Math.Round(thickness*100);Pen p;if(!group.TryGetValue(key,out p)){p=new Pen(Frozen(color),key/100.0);p.Freeze();group[key]=p;}return p;}
        private void BuildTypes()
        {
            types.Add(new HeroType{Id="gondor",Name="Аста · анти-магический клинок",Icon="⚔",Price=70,Damage=17,Range=185,Rate=.85,Description="Быстрый ближний удар",Special="Атакует сразу три цели",Sprite="gondor",UpgradeCosts=new[]{80,125,190,290},Forms=new[]{"Аста","Чёрный бык","Демон-истребитель","Чёрная форма","Анти-магический Аста"}});
            types.Add(new HeroType{Id="elf",Name="Юно · магия ветра",Icon="✧",Price=100,Damage=28,Range=225,Rate=1.2,Description="Дальний порыв ветра",Special="Снаряд пробивает строй",Sprite="elf",UpgradeCosts=new[]{90,140,205,310},Forms=new[]{"Юно","Ветер Зефира","Дух ветра","Золотая корона","Духовой шквал"}});
            types.Add(new HeroType{Id="dwarf",Name="Магна · огненный шар",Icon="🔥",Price=125,Damage=45,Range=155,Rate=1.05,Description="Взрывной огненный удар",Special="Взрыв задевает соседей",Sprite="dwarf",UpgradeCosts=new[]{95,145,215,320},Forms=new[]{"Магна","Красная нить","Пылающий мяч","Огненная броня","Великий огненный шар"}});
            types.Add(new HeroType{Id="aura",Name="Ванесса · красная нить",Icon="✦",Price=115,Damage=0,Range=185,Rate=0,Description="Аура скорости или урона",Special="Широкая усиленная аура",Sprite="aura",UpgradeCosts=new[]{95,145,220,330},Forms=new[]{"Ванесса","Красная нить судьбы","Нить защиты","Алая судьба","Нить судьбы: сильная аура"}});
            types.Add(new HeroType{Id="ice",Name="Ноэль · магия воды",Icon="❄",Price=120,Damage=18,Range=192,Rate=1.25,Description="Залп воды замедляет",Special="Почти полностью замораживает",Sprite="ice",UpgradeCosts=new[]{95,145,215,320},Forms=new[]{"Ноэль","Серебряное копьё","Водная броня","Морской дракон","Валькирия: ледяной плен"}});
        }
        private BitmapSource LoadSprite(string file,int pixelWidth){if(!File.Exists(file))return null;BitmapImage image=new BitmapImage();image.BeginInit();image.CacheOption=BitmapCacheOption.OnLoad;if(pixelWidth>0)image.DecodePixelWidth=pixelWidth;image.UriSource=new Uri(file,UriKind.Absolute);image.EndInit();image.Freeze();return image;}
        private void BuildUi()
        {
            effectVolumeDelay=new DispatcherTimer(DispatcherPriority.Background);effectVolumeDelay.Interval=TimeSpan.FromMilliseconds(110);effectVolumeDelay.Tick+=delegate{effectVolumeDelay.Stop();audio.SetEffectVolume(pendingEffectVolume);};
            Grid rootGrid=new Grid();rootGrid.RowDefinitions.Add(new RowDefinition{Height=new GridLength(84)});rootGrid.RowDefinitions.Add(new RowDefinition{Height=new GridLength(1,GridUnitType.Star)});Content=rootGrid;
            UIElement header=BuildHeader();Grid.SetRow(header,0);rootGrid.Children.Add(header);
            Grid main=new Grid{Margin=new Thickness(12,8,12,12)};main.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});main.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(390)});Grid.SetRow(main,1);rootGrid.Children.Add(main);
            Border playFrame=new Border{Margin=new Thickness(0,0,12,0),Padding=new Thickness(3),Background=Brushed(28,35,34,48,41,27,24),BorderBrush=Brushed(171,137,79,90,76,58,44),BorderThickness=new Thickness(2)};main.Children.Add(playFrame);
            Grid playGrid=new Grid();playGrid.RowDefinitions.Add(new RowDefinition{Height=new GridLength(1,GridUnitType.Star)});playGrid.RowDefinitions.Add(new RowDefinition{Height=new GridLength(31)});playFrame.Child=playGrid;
            worldView=new Viewport3D{ClipToBounds=true,IsHitTestVisible=false};worldCamera=new OrthographicCamera{Position=new Point3D(WorldW*.5,5000,WorldH*.5),LookDirection=new Vector3D(0,-.53,-.85),UpDirection=new Vector3D(0,.85,-.53),Width=WorldW,NearPlaneDistance=1,FarPlaneDistance=12000};worldView.Camera=worldCamera;RenderOptions.SetBitmapScalingMode(worldView,BitmapScalingMode.HighQuality);
            Model3DGroup lights=new Model3DGroup();lights.Children.Add(new AmbientLight(Color.FromRgb(183,192,202)));lights.Children.Add(new DirectionalLight(Color.FromRgb(255,239,213),new Vector3D(.25,-1,-.35)));lights.Children.Add(new DirectionalLight(Color.FromRgb(95,127,158),new Vector3D(-.7,-.45,.4)));lightVisual=new ModelVisual3D{Content=lights};worldView.Children.Add(lightVisual);groundVisual=new ModelVisual3D();worldView.Children.Add(groundVisual);playGrid.Children.Add(worldView);
            surface=new GameSurface(this);Panel.SetZIndex(surface,2);playGrid.Children.Add(surface);Border zoomBox=new Border{Padding=new Thickness(4),Margin=new Thickness(12),HorizontalAlignment=HorizontalAlignment.Right,VerticalAlignment=VerticalAlignment.Top,Background=Brushed(235,17,24,29,34,43,48),BorderBrush=Brushed(230,197,155,91,87,109,116),BorderThickness=new Thickness(1)};StackPanel zoomControls=new StackPanel{Orientation=Orientation.Horizontal};Button zoomOut=GoldButton("−",34,32);zoomOut.Margin=new Thickness(1);zoomOut.Click+=delegate{ChangeZoom(-120);};zoomLabel=new TextBlock{Text="100%",Foreground=gold,FontWeight=FontWeights.Bold,FontSize=11,Width=52,VerticalAlignment=VerticalAlignment.Center,TextAlignment=TextAlignment.Center};Button zoomIn=GoldButton("+",34,32);zoomIn.Margin=new Thickness(1);zoomIn.Click+=delegate{ChangeZoom(120);};zoomControls.Children.Add(zoomOut);zoomControls.Children.Add(zoomLabel);zoomControls.Children.Add(zoomIn);zoomBox.Child=zoomControls;Panel.SetZIndex(zoomBox,4);playGrid.Children.Add(zoomBox);
            Border footer=new Border{Background=Brushed(31,39,39,26,33,27,23),Padding=new Thickness(10,5,10,5),BorderBrush=Brushed(100,139,116,69),BorderThickness=new Thickness(0,1,0,0)};Grid.SetRow(footer,1);playGrid.Children.Add(footer);statusText=new TextBlock{Foreground=muted,VerticalAlignment=VerticalAlignment.Center,Text="Выбери героя, затем место на поле · колёсико мыши — масштаб"};footer.Child=statusText;
            Border side=BuildSidePanel();Grid.SetColumn(side,1);main.Children.Add(side);
            Border overlay=BuildOverlay();Grid.SetRow(overlay,0);playGrid.Children.Add(overlay);overlayBorder=overlay;overlay.Visibility=Visibility.Collapsed;
            Border pause=BuildPauseOverlay();Grid.SetRow(pause,0);playGrid.Children.Add(pause);pauseBorder=pause;pause.Visibility=Visibility.Collapsed;
        }
        private static Brush Brushed(byte a,byte r1,byte g1,byte b1){return Frozen(Color.FromArgb(a,r1,g1,b1));}
        private static Brush Brushed(byte a,byte r1,byte g1,byte b1,byte r2,byte g2,byte b2){LinearGradientBrush b=new LinearGradientBrush(Color.FromArgb(a,r1,g1,b1),Color.FromArgb(a,r2,g2,b2),90);b.Freeze();return b;}
        private static Brush StoneTexture()
        {
            if(stoneTextureBrush!=null)return stoneTextureBrush;DrawingGroup tile=new DrawingGroup();using(DrawingContext dc=tile.Open()){LinearGradientBrush baseStone=new LinearGradientBrush(Color.FromRgb(44,57,66),Color.FromRgb(19,27,35),90);baseStone.Freeze();dc.DrawRectangle(baseStone,null,new Rect(0,0,128,128));Random r=new Random(7331);for(int i=0;i<46;i++){double x=r.Next(0,128),y=r.Next(0,128),w=4+r.NextDouble()*17,h=.5+r.NextDouble()*1.4;Color edge=i%5==0?Color.FromArgb(30,213,186,128):Color.FromArgb(25,166,191,198);dc.DrawLine(Stroke(edge,h),new Point(x,y),new Point(Math.Min(127,x+w),y+(r.NextDouble()-.5)*3));if(i%3==0)dc.DrawEllipse(Frozen(Color.FromArgb(18,7,14,19)),null,new Point(x,y+5),1+r.NextDouble()*2,.7+r.NextDouble());}}
            tile.Freeze();DrawingBrush brush=new DrawingBrush(tile){TileMode=TileMode.Tile,Stretch=Stretch.Fill,Viewport=new Rect(0,0,128,128),ViewportUnits=BrushMappingMode.Absolute,Viewbox=new Rect(0,0,128,128),ViewboxUnits=BrushMappingMode.Absolute};brush.Freeze();stoneTextureBrush=brush;return brush;
        }
        private UIElement BuildHeader()
        {
            Border frame=new Border{Padding=new Thickness(16,8,16,8),Background=Brushed(255,34,37,38,12,18,23),BorderBrush=Brushed(255,154,122,67,80,65,39),BorderThickness=new Thickness(0,0,0,2)};
            Grid grid=new Grid();grid.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(365)});grid.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});frame.Child=grid;
            StackPanel brand=new StackPanel{VerticalAlignment=VerticalAlignment.Center};brand.Children.Add(new TextBlock{Text="✦  РУБЕЖ СРЕДИЗЕМЬЯ",Foreground=gold,FontFamily=new FontFamily("Georgia"),FontSize=19,FontWeight=FontWeights.Bold});brand.Children.Add(new TextBlock{Text="ЧЁРНЫЙ КЛЕВЕР ЗАЩИЩАЕТ СРЕДИЗЕМЬЕ ОТ МОРДОРА",Foreground=muted,FontSize=10,Margin=new Thickness(4,3,0,0)});grid.Children.Add(brand);
            WrapPanel controls=new WrapPanel{HorizontalAlignment=HorizontalAlignment.Right,VerticalAlignment=VerticalAlignment.Center,Orientation=Orientation.Horizontal};Grid.SetColumn(controls,1);grid.Children.Add(controls);
            goldValue=new TextBlock();waveValue=new TextBlock();livesValue=new TextBlock();arenaValue=new TextBlock();controls.Children.Add(StatCard("ЗОЛОТО",goldValue));controls.Children.Add(StatCard("ВОЛНА",waveValue));controls.Children.Add(StatCard("РУБЕЖ",livesValue));controls.Children.Add(StatCard("АРЕНА",arenaValue));
            musicButton=GoldButton("♫  Музыка: вкл",120,46);musicButton.Margin=new Thickness(5,0,5,0);musicButton.Click+=delegate{musicOn=!musicOn;if(musicOn){audio.PlayMusic((int)musicSlider.Value);musicButton.Content="♫  Музыка: вкл";}else{audio.StopMusic();musicButton.Content="♫  Музыка: выкл";}};controls.Children.Add(musicButton);
            controls.Children.Add(VolumeControl("МУЗЫКА",true));controls.Children.Add(VolumeControl("ЗВУК МАГИИ",false));Button full=GoldButton("⛶ Экран",90,46);full.Margin=new Thickness(5,0,0,0);full.Click+=delegate{ToggleFullscreen(full);};controls.Children.Add(full);
            return frame;
        }
        private UIElement StatCard(string caption,TextBlock value){Border b=new Border{Width=69,Height=48,Margin=new Thickness(3,0,3,0),Padding=new Thickness(3),Background=Brushed(255,38,43,45,22,29,34),BorderBrush=Brushed(255,142,112,62,79,67,47),BorderThickness=new Thickness(1)};StackPanel s=new StackPanel{VerticalAlignment=VerticalAlignment.Center};value.TextAlignment=TextAlignment.Center;value.Foreground=gold;value.FontSize=16;value.FontWeight=FontWeights.Bold;s.Children.Add(value);s.Children.Add(new TextBlock{Text=caption,TextAlignment=TextAlignment.Center,Foreground=muted,FontSize=8});b.Child=s;return b;}
        private UIElement VolumeControl(string label,bool music)
        {
            Border box=new Border{Width=143,Height=50,Margin=new Thickness(3,0,3,0),Padding=new Thickness(5,3,5,2),Background=Brushed(255,43,57,65,21,29,38),BorderBrush=Brushed(255,112,143,151,68,92,101),BorderThickness=new Thickness(1)};Grid grid=new Grid();grid.RowDefinitions.Add(new RowDefinition{Height=new GridLength(14)});grid.RowDefinitions.Add(new RowDefinition{Height=new GridLength(1,GridUnitType.Star)});box.Child=grid;
            TextBlock text=new TextBlock{Text=label,Foreground=muted,FontSize=8,FontWeight=FontWeights.Bold};grid.Children.Add(text);Slider slider=new Slider{Minimum=0,Maximum=music?100:1000,Value=music?12:350,TickFrequency=music?25:100,IsSnapToTickEnabled=false,IsMoveToPointEnabled=true,SmallChange=1,LargeChange=music?5:10,VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(0,0,35,0),Foreground=Brushed(255,157,203,211),Background=Brushed(255,37,45,53)};slider.Template=CreateSliderTemplate();Grid.SetRow(slider,1);grid.Children.Add(slider);TextBlock value=new TextBlock{Text=music?"12%":"35.0%",Foreground=gold,FontSize=9,HorizontalAlignment=HorizontalAlignment.Right,VerticalAlignment=VerticalAlignment.Center,Width=37};Grid.SetRow(value,1);grid.Children.Add(value);
            slider.ValueChanged+=delegate{if(music){value.Text=Math.Round(slider.Value)+"%";musicSlider=slider;audio.SetMusicVolume((int)slider.Value);}else{value.Text=(slider.Value/10.0).ToString("0.0")+"%";magicSlider=slider;pendingEffectVolume=slider.Value;effectVolumeDelay.Stop();effectVolumeDelay.Start();}};if(music)musicSlider=slider;else magicSlider=slider;return box;
        }
        private Border BuildSidePanel()
        {
            Border outer=new Border{Padding=new Thickness(5),Background=Brushed(255,173,143,91,48,37,29),BorderBrush=Brushed(255,235,205,145,101,132,151),BorderThickness=new Thickness(3)};
            Grid frame=new Grid();outer.Child=frame;
            Border stone=new Border{Margin=new Thickness(2),Background=StoneTexture(),BorderBrush=Brushed(255,171,159,130,64,82,93),BorderThickness=new Thickness(2)};frame.Children.Add(stone);
            Border inset=new Border{Margin=new Thickness(8),BorderBrush=Brushed(225,233,198,135,106,153,171),BorderThickness=new Thickness(1.2)};frame.Children.Add(inset);
            Grid tracery=new Grid{IsHitTestVisible=false,Margin=new Thickness(8)};frame.Children.Add(tracery);
            TextBlock[] corners={new TextBlock{Text="❖",HorizontalAlignment=HorizontalAlignment.Left,VerticalAlignment=VerticalAlignment.Top,Margin=new Thickness(0)},new TextBlock{Text="❖",HorizontalAlignment=HorizontalAlignment.Right,VerticalAlignment=VerticalAlignment.Top,Margin=new Thickness(0)},new TextBlock{Text="❖",HorizontalAlignment=HorizontalAlignment.Left,VerticalAlignment=VerticalAlignment.Bottom,Margin=new Thickness(0)},new TextBlock{Text="❖",HorizontalAlignment=HorizontalAlignment.Right,VerticalAlignment=VerticalAlignment.Bottom,Margin=new Thickness(0)}};foreach(TextBlock corner in corners){corner.Foreground=Brushed(210,133,185,196);corner.FontSize=16;corner.FontFamily=new FontFamily("Georgia");tracery.Children.Add(corner);}
            Border leftRune=new Border{Width=1,HorizontalAlignment=HorizontalAlignment.Left,VerticalAlignment=VerticalAlignment.Stretch,Margin=new Thickness(2,28,0,28),Background=Brushed(52,105,174,188)};tracery.Children.Add(leftRune);Border rightRune=new Border{Width=1,HorizontalAlignment=HorizontalAlignment.Right,VerticalAlignment=VerticalAlignment.Stretch,Margin=new Thickness(2,28,0,28),Background=Brushed(52,105,174,188)};tracery.Children.Add(rightRune);
            ScrollViewer scroll=new ScrollViewer{Margin=new Thickness(15,12,15,12),VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled};StackPanel content=new StackPanel();scroll.Content=content;frame.Children.Add(scroll);
            Border titleFrame=new Border{Margin=new Thickness(0,0,0,9),Padding=new Thickness(8,7,8,8),Background=Brushed(255,64,86,99,20,32,44),BorderBrush=Brushed(255,236,198,120,114,151,168),BorderThickness=new Thickness(2,2,2,3)};StackPanel titleStack=new StackPanel();titleFrame.Child=titleStack;titleStack.Children.Add(new TextBlock{Text="✧  АРСЕНАЛ МАГОВ  ✧",Foreground=gold,FontFamily=new FontFamily("Georgia"),FontWeight=FontWeights.Bold,FontSize=16,HorizontalAlignment=HorizontalAlignment.Center});titleStack.Children.Add(new TextBlock{Text="РУБЕЖ СРЕДИЗЕМЬЯ  ·  ОРДЕН ЗАЩИТНИКОВ",Foreground=Brushed(235,196,211,211),FontSize=8,HorizontalAlignment=HorizontalAlignment.Center,Margin=new Thickness(0,3,0,0)});content.Children.Add(titleFrame);
            cardsPanel=new StackPanel();content.Children.Add(cardsPanel);
            Grid waveControls=new Grid{Margin=new Thickness(0,7,0,8)};waveControls.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});waveControls.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(104)});startButton=GoldButton("▶  Начать волну",0,43);startButton.HorizontalAlignment=HorizontalAlignment.Stretch;startButton.Margin=new Thickness(0,0,5,0);startButton.Click+=delegate{StartWave();};waveControls.Children.Add(startButton);pauseButton=GoldButton("Ⅱ Пауза",0,43);pauseButton.IsEnabled=false;pauseButton.Margin=new Thickness(5,0,0,0);pauseButton.Click+=delegate{TogglePause();};Grid.SetColumn(pauseButton,1);waveControls.Children.Add(pauseButton);content.Children.Add(waveControls);
            TextBlock speedCaption=new TextBlock{Text="ТЕМП ИГРЫ",Foreground=muted,FontSize=9,FontWeight=FontWeights.Bold,Margin=new Thickness(2,2,0,4)};content.Children.Add(speedCaption);speedButton=GoldButton("1×   ▾",0,34);speedButton.HorizontalAlignment=HorizontalAlignment.Stretch;speedButton.HorizontalContentAlignment=HorizontalAlignment.Left;speedButton.Click+=delegate{speedPopup.IsOpen=!speedPopup.IsOpen;};content.Children.Add(speedButton);StackPanel speeds=new StackPanel{Width=318};string[] speedNames={"0,75×   Медленный","1×   Обычный","1,5×   Быстрый","2×   Стремительный","3×   Молниеносный"};double[] speedValues={.75,1,1.5,2,3};for(int i=0;i<speedNames.Length;i++){int ix=i;Button option=GoldButton(speedNames[i],0,34);option.HorizontalAlignment=HorizontalAlignment.Stretch;option.HorizontalContentAlignment=HorizontalAlignment.Left;option.Margin=new Thickness(2);option.Click+=delegate{gameSpeed=speedValues[ix];speedButton.Content=speedNames[ix].Split(' ')[0]+"   ▾";speedPopup.IsOpen=false;};speeds.Children.Add(option);}Border popupFrame=new Border{Padding=new Thickness(5),Background=Brushed(255,43,58,67,16,23,31),BorderBrush=Brushed(255,184,169,128,91,148,160),BorderThickness=new Thickness(2),Child=speeds};speedPopup=new Popup{PlacementTarget=speedButton,Placement=PlacementMode.Bottom,StaysOpen=false,AllowsTransparency=true,PopupAnimation=PopupAnimation.Fade,Child=popupFrame};
            UIElement section=Section("РАЗВЕДКА И УЛУЧШЕНИЯ");content.Children.Add(section);selectionText=new TextBlock{Text="Выбери мага, чтобы увидеть его способности.",Foreground=ivory,TextWrapping=TextWrapping.Wrap,FontSize=12,MinHeight=82,Margin=new Thickness(2,5,2,8)};content.Children.Add(selectionText);
            Grid actions=new Grid();actions.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});actions.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});upgradeButton=GoldButton("Улучшить",0,39);upgradeButton.IsEnabled=false;upgradeButton.Margin=new Thickness(0,0,4,0);upgradeButton.Click+=delegate{Upgrade();};actions.Children.Add(upgradeButton);sellButton=GoldButton("Продать",0,39);sellButton.IsEnabled=false;sellButton.Margin=new Thickness(4,0,0,0);sellButton.Click+=delegate{Sell();};Grid.SetColumn(sellButton,1);actions.Children.Add(sellButton);content.Children.Add(actions);
            Grid auras=new Grid{Margin=new Thickness(0,7,0,10),Visibility=Visibility.Collapsed};auras.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});auras.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});auraSpeedButton=GoldButton("Аура скорости",0,36);auraSpeedButton.Margin=new Thickness(0,0,4,0);auraSpeedButton.Click+=delegate{SetAura("speed");};auras.Children.Add(auraSpeedButton);auraDamageButton=GoldButton("Аура урона",0,36);auraDamageButton.Margin=new Thickness(4,0,0,0);auraDamageButton.Click+=delegate{SetAura("damage");};Grid.SetColumn(auraDamageButton,1);auras.Children.Add(auraDamageButton);content.Children.Add(auras);auraButtons=auras;
            content.Children.Add(Section("СВОДКА РУБЕЖА"));TextBlock help=new TextBlock{Text="Кампания: 18 арен по 15 волн. У каждой земли свой путь; карты постепенно становятся крупнее. Уничтожай отряды Мордора, получай золото и развивай магов. Четвёртый уровень открывает особую силу.\n\nКлик по магу на поле — выбрать его. Колёсико или кнопки +/− — масштаб; P — пауза, Space — следующая волна.",Foreground=muted,TextWrapping=TextWrapping.Wrap,FontSize=10,Margin=new Thickness(2,4,2,8)};content.Children.Add(help);return outer;
        }
        private UIElement auraButtons;
        private UIElement Section(string text){Border b=new Border{Margin=new Thickness(0,9,0,4),Padding=new Thickness(7,5,7,5),Background=Brushed(255,49,67,79,20,31,43),BorderBrush=Brushed(220,184,166,122,96,154,170),BorderThickness=new Thickness(1)};Grid row=new Grid();row.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(18)});row.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});row.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(18)});TextBlock left=new TextBlock{Text="✦",Foreground=Brushed(245,157,216,227),FontSize=11,VerticalAlignment=VerticalAlignment.Center};TextBlock label=new TextBlock{Text=text,Foreground=gold,FontFamily=new FontFamily("Georgia"),FontWeight=FontWeights.Bold,FontSize=11,VerticalAlignment=VerticalAlignment.Center};TextBlock right=new TextBlock{Text="✦",Foreground=Brushed(245,157,216,227),FontSize=11,VerticalAlignment=VerticalAlignment.Center,HorizontalAlignment=HorizontalAlignment.Right};row.Children.Add(left);Grid.SetColumn(label,1);row.Children.Add(label);Grid.SetColumn(right,2);row.Children.Add(right);b.Child=row;return b;}
        private Button GoldButton(string text,double width,double height)
        {
            Button b=new Button{Content=text,Width=width>0?width:double.NaN,Height=height,Padding=new Thickness(7,4,7,4),Foreground=ivory,Background=Brushed(255,79,101,114,25,37,49),BorderBrush=Brushed(255,216,184,117,98,132,148),BorderThickness=new Thickness(2),FontFamily=new FontFamily("Georgia"),FontWeight=FontWeights.SemiBold,FontSize=11,Cursor=Cursors.Hand,HorizontalContentAlignment=HorizontalAlignment.Center,VerticalContentAlignment=VerticalAlignment.Center,Focusable=true};
            FrameworkElementFactory frame=new FrameworkElementFactory(typeof(Border),"Frame");frame.SetValue(Border.CornerRadiusProperty,new CornerRadius(0));frame.SetBinding(Border.BackgroundProperty,new Binding("Background"){RelativeSource=RelativeSource.TemplatedParent});frame.SetBinding(Border.BorderBrushProperty,new Binding("BorderBrush"){RelativeSource=RelativeSource.TemplatedParent});frame.SetBinding(Border.BorderThicknessProperty,new Binding("BorderThickness"){RelativeSource=RelativeSource.TemplatedParent});
            FrameworkElementFactory presenter=new FrameworkElementFactory(typeof(ContentPresenter));presenter.SetBinding(ContentPresenter.ContentProperty,new Binding("Content"){RelativeSource=RelativeSource.TemplatedParent});presenter.SetBinding(ContentPresenter.ContentTemplateProperty,new Binding("ContentTemplate"){RelativeSource=RelativeSource.TemplatedParent});presenter.SetBinding(ContentPresenter.HorizontalAlignmentProperty,new Binding("HorizontalContentAlignment"){RelativeSource=RelativeSource.TemplatedParent});presenter.SetBinding(ContentPresenter.VerticalAlignmentProperty,new Binding("VerticalContentAlignment"){RelativeSource=RelativeSource.TemplatedParent});presenter.SetValue(FrameworkElement.MarginProperty,new Thickness(3));frame.AppendChild(presenter);
            ControlTemplate template=new ControlTemplate(typeof(Button));template.VisualTree=frame;Trigger hover=new Trigger{Property=Button.IsMouseOverProperty,Value=true};hover.Setters.Add(new Setter(Border.BackgroundProperty,Brushed(255,93,139,158,31,61,76),"Frame"));hover.Setters.Add(new Setter(Border.BorderBrushProperty,Brushed(255,226,202,147),"Frame"));template.Triggers.Add(hover);Trigger pressed=new Trigger{Property=Button.IsPressedProperty,Value=true};pressed.Setters.Add(new Setter(Border.BackgroundProperty,Brushed(255,28,44,56,10,19,28),"Frame"));template.Triggers.Add(pressed);Trigger disabled=new Trigger{Property=Button.IsEnabledProperty,Value=false};disabled.Setters.Add(new Setter(Border.BackgroundProperty,Brushed(255,37,46,51,22,28,34),"Frame"));disabled.Setters.Add(new Setter(Border.BorderBrushProperty,Brushed(255,91,112,117),"Frame"));disabled.Setters.Add(new Setter(Border.OpacityProperty,.58,"Frame"));template.Triggers.Add(disabled);b.Template=template;return b;
        }
        private ControlTemplate CreateSliderTemplate(){string xaml="<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' TargetType='{x:Type Slider}' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'><Grid Height='24'><Border Height='4' VerticalAlignment='Center' CornerRadius='2' Background='#FF292F34'/><Track x:Name='PART_Track' Orientation='Horizontal' Minimum='{TemplateBinding Minimum}' Maximum='{TemplateBinding Maximum}' Value='{Binding Value, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}'><Track.Thumb><Thumb Width='14' Height='19' Background='#FFE8C17B' BorderBrush='#FFFFE7B3' BorderThickness='1'><Thumb.Template><ControlTemplate TargetType='{x:Type Thumb}'><Border CornerRadius='3' Background='#FFE8C17B' BorderBrush='#FFFFE7B3' BorderThickness='1'/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb></Track></Grid></ControlTemplate>";return (ControlTemplate)XamlReader.Parse(xaml);}
        private Border BuildOverlay()
        {
            Border b=new Border{Width=520,Height=200,Padding=new Thickness(28),HorizontalAlignment=HorizontalAlignment.Center,VerticalAlignment=VerticalAlignment.Center,Background=Brushed(245,33,35,34,12,18,23),BorderBrush=Brushed(255,218,177,98,114,84,49),BorderThickness=new Thickness(3),IsHitTestVisible=false};StackPanel s=new StackPanel{VerticalAlignment=VerticalAlignment.Center};overlayHeading=new TextBlock{Text="Держи рубеж!",FontFamily=new FontFamily("Georgia"),FontSize=28,FontWeight=FontWeights.Bold,Foreground=gold,TextAlignment=TextAlignment.Center,Margin=new Thickness(0,0,0,12)};overlayBody=new TextBlock{Text="Расставь магов рядом с дорогой и пройди кампанию из 18 арен по 15 волн.",Foreground=ivory,TextAlignment=TextAlignment.Center,TextWrapping=TextWrapping.Wrap,Margin=new Thickness(5,0,5,14)};s.Children.Add(overlayHeading);s.Children.Add(overlayBody);b.Child=s;return b;
        }
        private Border BuildPauseOverlay(){Border b=new Border{Width=300,Height=94,Padding=new Thickness(20),HorizontalAlignment=HorizontalAlignment.Center,VerticalAlignment=VerticalAlignment.Center,Background=Brushed(236,27,31,33,11,15,18),BorderBrush=Brushed(255,218,177,98,114,84,49),BorderThickness=new Thickness(3)};b.Child=new TextBlock{Text="ПАУЗА",Foreground=gold,FontFamily=new FontFamily("Georgia"),FontSize=30,FontWeight=FontWeights.Bold,TextAlignment=TextAlignment.Center,VerticalAlignment=VerticalAlignment.Center};return b;}

        private void RefreshHud(){if(goldValue==null)return;goldValue.Text=goldCount.ToString();waveValue.Text=waveInArena+"/"+WavesPerArena;livesValue.Text=lives.ToString();arenaValue.Text=(arenaIndex+1)+"/"+ArenaCount;}
        private void RefreshCards()
        {
            if(cardsPanel==null)return;
            if(cardButtons.Count==0)foreach(HeroType type in types){HeroType t=type;StackPanel content=new StackPanel{Orientation=Orientation.Horizontal,VerticalAlignment=VerticalAlignment.Center};TextBlock icon=new TextBlock{Text=t.Icon,Width=38,FontSize=22,Foreground=gold,VerticalAlignment=VerticalAlignment.Center,TextAlignment=TextAlignment.Center};StackPanel text=new StackPanel{Width=255,VerticalAlignment=VerticalAlignment.Center};text.Children.Add(new TextBlock{Text=t.Name,Foreground=ivory,FontWeight=FontWeights.Bold,FontSize=11,TextTrimming=TextTrimming.CharacterEllipsis});text.Children.Add(new TextBlock{Text=t.Price+" ✦   ·   "+t.Description,Foreground=muted,FontSize=9,TextTrimming=TextTrimming.CharacterEllipsis});content.Children.Add(icon);content.Children.Add(text);Button b=GoldButton("",0,66);b.HorizontalAlignment=HorizontalAlignment.Stretch;b.HorizontalContentAlignment=HorizontalAlignment.Left;b.Margin=new Thickness(0,2,0,4);b.Padding=new Thickness(5);b.Content=content;b.ToolTip=BuildHeroTooltip(t);ToolTipService.SetInitialShowDelay(b,350);ToolTipService.SetShowDuration(b,20000);ToolTipService.SetShowOnDisabled(b,true);b.Click+=delegate{selectedType=t;selectedTower=null;SetBuildGhost(t);RefreshCards();UpdateSelection();surface.InvalidateVisual();};cardButtons[t.Id]=b;cardsPanel.Children.Add(b);}
            foreach(HeroType t in types){Button b=cardButtons[t.Id];b.IsEnabled=goldCount>=t.Price;b.BorderBrush=selectedType==t?Brushed(255,242,209,135):Brushed(245,155,173,179,67,90,102);b.Background=selectedType==t?Brushed(255,83,99,105,30,49,60):Brushed(255,48,63,73,18,29,39);}
        }
        private ToolTip BuildHeroTooltip(HeroType t)
        {
            StackPanel body=new StackPanel{Width=245};body.Children.Add(new TextBlock{Text=t.Name,Foreground=gold,FontFamily=new FontFamily("Georgia"),FontSize=14,FontWeight=FontWeights.Bold,TextWrapping=TextWrapping.Wrap,Margin=new Thickness(0,0,0,5)});body.Children.Add(new TextBlock{Text=t.Description,Foreground=ivory,FontSize=11,TextWrapping=TextWrapping.Wrap,Margin=new Thickness(0,0,0,7)});string stats=t.Id=="aura"?"Аура: радиус "+(int)t.Range+", усиление 30%":"Урон: "+t.Damage+"   ·   Дальность: "+(int)t.Range+(t.Rate>0?"\nСкорость: "+(1/t.Rate).ToString("0.0")+" атаки/с":"");body.Children.Add(new TextBlock{Text=stats,Foreground=ColorBrush(Color.FromRgb(208,190,143)),FontSize=10,TextWrapping=TextWrapping.Wrap,Margin=new Thickness(0,0,0,7)});body.Children.Add(new Border{Height=1,Background=Brushed(160,173,133,75),Margin=new Thickness(0,2,0,6)});body.Children.Add(new TextBlock{Text="Особенность: "+t.Special,Foreground=ivory,FontSize=10,TextWrapping=TextWrapping.Wrap});body.Children.Add(new TextBlock{Text="Стоимость: "+t.Price+" золота · 4 улучшения",Foreground=gold,FontSize=10,Margin=new Thickness(0,8,0,0)});Border frame=new Border{Padding=new Thickness(12),Background=Brushed(246,34,37,38,13,19,25),BorderBrush=Brushed(255,194,155,85),BorderThickness=new Thickness(2),Child=body};return new ToolTip{Content=frame,Background=Brushed(0,0,0,0),BorderThickness=new Thickness(0),Padding=new Thickness(0),Placement=PlacementMode.Left,HasDropShadow=true};
        }
        private Brush ColorBrush(Color c){return Frozen(c);}
        private void UpdateSelection()
        {
            if(selectionText==null)return;bool aura=selectedTower!=null&&selectedTower.Type.Id=="aura";auraButtons.Visibility=aura?Visibility.Visible:Visibility.Collapsed;
            if(selectedTower==null){upgradeButton.IsEnabled=false;sellButton.IsEnabled=false;selectionText.Text=selectedType==null?"Выбери мага, чтобы увидеть его способности.":selectedType.Name+"\n\nНаведи курсор на поле: призрак покажет точку установки.";return;}
            Tower t=selectedTower;HeroType d=t.Type;double dm,sp;Buff(t,out dm,out sp);string next=t.Level<4?"\nСледующий уровень: "+d.Forms[t.Level+1]:"\nОсобенность: "+d.Special;string stat;if(d.Id=="aura")stat="Радиус: "+(int)(t.Range/MapScale)+"\nУсиление: +"+(int)Math.Round(t.Power*100)+"% к "+(t.Aura=="damage"?"урону":"скорости атаки");else{stat="Урон: "+(int)t.Damage+(dm>1.0001?" (+"+Math.Round((dm-1)*100)+"% аур, итого "+(int)Math.Round(t.Damage*dm)+")":"")+"\nДальность: "+(int)(t.Range/MapScale)+"\nСкорость: "+(1/t.Rate).ToString("0.0")+" выстр./с"+(sp>1.0001?" (аура +"+Math.Round((sp-1)*100)+"% → "+(1/t.Rate*sp).ToString("0.0")+")":"");if(dm<=1.0001&&sp<=1.0001)stat+="\nАура: нет усиления";}
            selectionText.Text=d.Forms[t.Level]+" · уровень "+(t.Level+1)+"\n"+stat+next;upgradeButton.IsEnabled=t.Level<4&&goldCount>=d.UpgradeCosts[t.Level];upgradeButton.Content=t.Level<4?"Улучшить · "+d.UpgradeCosts[t.Level]+" ✦":"Максимум";sellButton.IsEnabled=true;auraSpeedButton.Background=t.Aura=="speed"?Brushed(255,106,91,49,47,59,48):Brushed(255,55,53,49,36,41,44);auraDamageButton.Background=t.Aura=="damage"?Brushed(255,119,78,37,53,48,42):Brushed(255,55,53,49,36,41,44);
        }
        private void UpdateStatus(string s){statusText.Text=s;}
        private void OnFrame(object sender,EventArgs e)
        {
            double now=frameClock.Elapsed.TotalSeconds;if(now-lastRender<1.0/60.0)return;lastRender=now;double dt=Math.Max(.001,Math.Min(.05,now-lastFrame));lastFrame=now;
            if(AdvanceZoom(dt)&&surface!=null)surface.InvalidateVisual();if(paused)return;if(overlayBorder.Visibility==Visibility.Visible){clock+=dt;UpdateTowerModels();UpdateEnemyModels();UpdateBoltModels();UpdateAmbientCritters();surface.InvalidateVisual();return;}
            if(waveRunning||enemies.Count>0||bolts.Count>0||bursts.Count>0||towers.Count>0||selectedType!=null||ambientCritters.Count>0||birds.Count>0){TickGame(dt*gameSpeed);UpdateTowerModels();UpdateEnemyModels();UpdateBoltModels();UpdateAmbientCritters();surface.InvalidateVisual();}
        }
        private void OnKeyDown(object sender,KeyEventArgs e){if(e.Key==Key.Escape){selectedType=null;SetBuildGhost(null);UpdateSelection();RefreshCards();surface.InvalidateVisual();}else if(e.Key==Key.Space){if(paused)TogglePause();else StartWave();e.Handled=true;}else if(e.Key==Key.P)TogglePause();else if(e.Key==Key.F11)ToggleFullscreen(null);else if(e.Key==Key.Add||e.Key==Key.OemPlus)ChangeZoom(120);else if(e.Key==Key.Subtract||e.Key==Key.OemMinus)ChangeZoom(-120);}
        private void ToggleFullscreen(Button button){fullScreen=!fullScreen;if(fullScreen){WindowStyle=WindowStyle.None;WindowState=WindowState.Maximized;if(button!=null)button.Content="Оконный";}else{WindowStyle=WindowStyle.SingleBorderWindow;WindowState=WindowState.Maximized;if(button!=null)button.Content="⛶ Экран";}}
        private void SetArenaPath()
        {
            MapScale=1+Math.Min(ArenaCount-1,arenaIndex)*.018;WorldW=BaseWorldW*MapScale;WorldH=BaseWorldH*MapScale;viewCenterX=WorldW*.5;viewCenterY=WorldH*.5;targetZoom=Zoom=1;targetCenterX=viewCenterX;targetCenterY=viewCenterY;
            Point[][] routes=new Point[][]{
                Route(0,.22,.10,.22,.17,.28,.19,.42,.27,.48,.36,.44,.40,.33,.48,.27,.58,.30,.63,.41,.61,.56,.54,.63,.45,.60,.41,.51,.46,.43,.58,.43,.70,.48,.78,.57,.77,.70,.71,.78,.73,.85,.85,.86,.93,.82,1,.81),
                Route(0,.68,.10,.69,.19,.63,.24,.51,.33,.43,.43,.44,.49,.53,.45,.64,.36,.72,.30,.80,.34,.87,.47,.88,.58,.82,.64,.71,.63,.57,.59,.47,.61,.37,.70,.29,.82,.28,.90,.34,.91,.44,.85,.52,.76,.51,.72,.44,.79,.37,.91,.38,1,.40),
                Route(1,.72,.91,.71,.85,.63,.78,.54,.75,.43,.79,.34,.87,.25,.84,.17,.76,.12,.65,.16,.56,.25,.51,.35,.54,.45,.64,.52,.70,.59,.70,.68,.63,.75,.53,.78,.43,.74,.34,.65,.29,.55,.31,.45,.39,.38,.49,.35,.60,.38,.71,.45,.77,.54,.74,.62,.65,.66,.55,.63,.46,.57,.38,.49,.29,.44,.18,.46,.09,.52,0,.55),
                Route(0,.36,.08,.36,.16,.44,.21,.54,.20,.62,.15,.72,.17,.81,.25,.86,.35,.84,.44,.77,.50,.68,.53,.58,.52,.48,.48,.39,.43,.32,.41,.25,.46,.18,.56,.14,.67,.16,.77,.23,.82,.33,.80,.43,.73,.50,.64,.55,.54,.57,.44,.62,.36,.70,.31,.79,.32,.87,.39,.92,.50,.93,.61,.88,.69,.77,.72,.65,.70,.54,.64,.48,.55,.47,.46,.52,.39,.61,.38,.69,.44,.74,.54,.74,.65,.69,.75,.60,.82,.49,.85,.39,.82,.31,.75,.27,.66,.30,.58,.37,.54,.45,.58,.52,.69,.55,.82,.52,.94,.47,1,.45),
                Route(1,.20,.92,.24,.85,.30,.77,.37,.73,.46,.76,.53,.83,.61,.86,.70,.82,.78,.74,.82,.64,.80,.54,.73,.49,.64,.50,.55,.56,.48,.65,.44,.75,.45,.83,.51,.87,.60,.84,.68,.77,.73,.68,.73,.58,.69,.50,.61,.44,.51,.43,.42,.47,.34,.55,.29,.64,.29,.73,.34,.78,.42,.77,.50,.71,.55,.62,.55,.54,.50,.49,.42,.50,.33,.56,.27,.66,.23,.78,.24,.88,.30,.94,.39,1,.41),
                Route(0,.78,.08,.76,.16,.68,.21,.58,.19,.49,.14,.40,.16,.33,.24,.30,.34,.34,.43,.43,.47,.53,.45,.63,.39,.72,.35,.81,.38,.88,.47,.91,.56,.88,.65,.80,.70,.70,.73,.59,.72,.49,.67,.42,.58,.39,.49,.42,.42,.49,.39,.58,.43,.66,.51,.70,.60,.68,.68,.62,.74,.53,.78,.43,.76,.33,.70,.26,.60,.24,.50,.27,.42,.34,.38,.43,.40,.52,.47,.58,.57,.59,.67,.55,.76,.49,.86,.45,.94,.46,1,.50),
                Route(1,.66,.92,.66,.84,.58,.78,.48,.78,.38,.82,.30,.86,.22,.83,.15,.75,.12,.65,.18,.58,.27,.54,.38,.53,.48,.58,.56,.67,.62,.74,.70,.73,.78,.67,.84,.57,.85,.47,.80,.39,.72,.32,.62,.28,.52,.32,.43,.41,.37,.52,.35,.62,.39,.70,.47,.72,.56,.66,.63,.57,.66,.48,.63,.40,.57,.34,.49,.32,.40,.36,.32,.43,.26,.53,.24,.63,.27,.73,.31,.83,.31,.91,.27,1,.24),
                Route(0,.30,.08,.30,.16,.37,.23,.47,.24,.57,.20,.67,.18,.77,.22,.84,.30,.86,.40,.81,.48,.72,.53,.62,.54,.52,.51,.43,.47,.35,.46,.27,.50,.20,.58,.15,.68,.16,.77,.21,.82,.29,.81,.37,.75,.43,.66,.46,.56,.45,.47,.42,.38,.43,.30,.48,.25,.56,.26,.64,.34,.69,.44,.70,.54,.68,.64,.63,.73,.56,.80,.48,.86,.40,.92,.35,1,.34),
                Route(1,.55,.92,.56,.84,.64,.78,.73,.78,.81,.84,.88,.82,.92,.75,.90,.66,.84,.58,.75,.54,.65,.55,.57,.61,.52,.70,.49,.79,.44,.84,.37,.83,.29,.77,.24,.68,.24,.60,.29,.54,.38,.50,.48,.49,.58,.52,.65,.59,.68,.68,.65,.76,.58,.78,.48,.75,.40,.68,.35,.59,.35,.50,.40,.43,.47,.39,.56,.39,.64,.43,.69,.51,.70,.60,.67,.69,.61,.76,.53,.83,.44,.90,.35,.94,.27,.90,.20,.82,.17,.72,.20,.64,.28,.60,.39,.61,.51,.65,.62,.72,.70,.81,.73,.91,.71,1,.67),
                Route(0,.44,.09,.44,.17,.52,.22,.62,.20,.70,.15,.78,.17,.84,.24,.83,.32,.77,.39,.68,.43,.58,.43,.49,.39,.41,.34,.34,.32,.27,.37,.21,.46,.18,.56,.20,.65,.26,.70,.34,.69,.43,.63,.49,.54,.52,.45,.51,.37,.47,.30,.48,.24,.54,.22,.62,.27,.68,.36,.72,.46,.73,.57,.70,.66,.65,.74,.58,.82,.51,.89,.47,.95,.46,1,.48),
                Route(1,.62,.92,.62,.84,.54,.79,.44,.80,.35,.85,.27,.84,.19,.78,.13,.69,.13,.60,.19,.55,.29,.54,.39,.59,.47,.68,.51,.77,.56,.82,.63,.81,.71,.74,.76,.64,.77,.54,.72,.47,.63,.43,.53,.44,.43,.48,.35,.55,.30,.64,.29,.74,.33,.82,.39,.87,.47,.85,.55,.78,.60,.68,.61,.57,.59,.48,.55,.41,.48,.37,.40,.41,.32,.49,.27,.59,.25,.70,.28,.80,.34,.88,.42,.93,.50,1,.53),
                Route(0,.22,.12,.22,.23,.28,.34,.40,.33,.52,.24,.60,.15,.68,.12,.79,.18,.87,.30,.88,.42,.81,.48,.70,.54,.61,.66,.59,.77,.66,.82,.77,.91,.83,1,.82),
                Route(1,.17,.90,.17,.81,.22,.74,.31,.73,.41,.80,.48,.88,.45,.94,.37,.95,.29,.88,.24,.78,.28,.71,.37,.66,.49,.69,.60,.77,.67,.85,.66,.92,.58,.97,.49,.94,.39,.86,.35,.76,.38,.65,.47,.60,.58,.65,.51,.73,.38,.77,.26,.73,.14,.64,.09,.52,.13,.42,.23,.39,.34,.43,.43,.51,.47,.61,.42,.70,.32,.76,.20,.74,.08,1,.06),
                Route(0,.12,.09,.18,.18,.25,.28,.32,.35,.42,.35,.54,.29,.63,.20,.68,.13,.76,.15,.86,.25,.90,.37,.87,.48,.79,.55,.69,.66,.66,.77,.71,.86,.80,.94,.84,1,.83),
                Route(1,.77,.90,.80,.80,.73,.70,.63,.69,.54,.75,.46,.84,.38,.86,.28,.79,.22,.68,.24,.58,.31,.52,.42,.53,.53,.61,.60,.71,.61,.81,.56,.87,.46,.84,.37,.76,.33,.66,.37,.58,.46,.56,.56,.62,.66,.73,.70,.83,.67,.91,.60,.94,.51,.90,.42,.81,.39,.70,.41,.61,.47,.55,.57,.55,.68,.63,.76,.74,.78,.85,.72,.92,.63,.96,.53,1,.43),
                Route(0,.84,.08,.80,.16,.72,.21,.63,.20,.54,.15,.45,.16,.37,.23,.34,.33,.38,.43,.47,.46,.57,.43,.66,.37,.73,.31,.81,.30,.88,.37,.91,.47,.87,.57,.79,.61,.68,.59,.58,.54,.50,.47,.46,.39,.48,.32,.54,.28,.63,.31,.72,.39,.77,.49,.74,.59,.68,.65,.58,.65,.47,.60,.38,.51,.35,.42,.38,.34,.47,.31,.57,.35,.67,.43,.72,.53,.73,.63,.69,.73,.62,.81,.53,.89,.46,.96,.43,1,.42),
                Route(1,.34,.91,.32,.82,.37,.73,.47,.68,.56,.71,.64,.80,.74,.84,.84,.80,.91,.72,.89,.62,.81,.54,.70,.51,.61,.54,.53,.62,.47,.73,.44,.84,.47,.91,.54,.93,.63,.88,.71,.78,.74,.67,.70,.59,.62,.54,.51,.56,.42,.65,.37,.76,.36,.87,.39,.93,.46,.95,.54,.90,.61,.80,.63,.69,.59,.59,.50,.53,.40,.56,.31,.65,.25,.76,.24,.87,.28,.95,.34,1,.38),
                Route(1,.12,.90,.12,.80,.17,.72,.27,.70,.38,.75,.47,.84,.45,.93,.37,.94,.28,.87,.23,.76,.26,.65,.34,.58,.45,.58,.56,.65,.63,.76,.65,.87,.60,.94,.52,.93,.42,.85,.37,.74,.40,.64,.48,.57,.58,.57,.68,.63,.76,.74,.78,.85,.72,.92,.63,.96,.53,1,.43)
            };
            path=ScaleRoute(routes[Math.Min(arenaIndex,routes.Length-1)]);BuildMotionPath();sceneCache=null;sceneCacheArena=-1;
        }
        private static Point[] Route(params double[] xy){Point[] result=new Point[xy.Length/2];for(int i=0;i<result.Length;i++)result[i]=new Point(xy[i*2],xy[i*2+1]);return result;}
        private Point[] ScaleRoute(Point[] route){Point[] result=new Point[route.Length];double marginX=78*MapScale,marginY=78*MapScale;for(int i=0;i<route.Length;i++){double x=route[i].X*WorldW,y=route[i].Y*WorldH;if(i==0||i==route.Length-1)x=x<WorldW*.5?Math.Max(52*MapScale,x):Math.Min(WorldW-52*MapScale,x);else x=Math.Max(marginX,Math.Min(WorldW-marginX,x));y=Math.Max(marginY,Math.Min(WorldH-marginY,y));result[i]=new Point(x,y);}return result;}
        private void BuildMotionPath()
        {
            List<Point> points=new List<Point>();const int steps=14;
            for(int i=0;i<path.Length-1;i++){Point p0=path[Math.Max(0,i-1)],p1=path[i],p2=path[i+1],p3=path[Math.Min(path.Length-1,i+2)];for(int j=0;j<steps;j++){double t=j/(double)steps,t2=t*t,t3=t2*t;double x=.5*((2*p1.X)+(-p0.X+p2.X)*t+(2*p0.X-5*p1.X+4*p2.X-p3.X)*t2+(-p0.X+3*p1.X-3*p2.X+p3.X)*t3);double y=.5*((2*p1.Y)+(-p0.Y+p2.Y)*t+(2*p0.Y-5*p1.Y+4*p2.Y-p3.Y)*t2+(-p0.Y+3*p1.Y-3*p2.Y+p3.Y)*t3);x=Math.Max(0,Math.Min(WorldW,x));y=Math.Max(65*MapScale,Math.Min(WorldH-65*MapScale,y));points.Add(new Point(x,y));}}points.Add(path[path.Length-1]);motionPath=points.ToArray();motionDistances=new double[motionPath.Length];routeLength=0;for(int i=1;i<motionPath.Length;i++){routeLength+=Distance(motionPath[i-1],motionPath[i]);motionDistances[i]=routeLength;}StreamGeometry geometry=new StreamGeometry();using(StreamGeometryContext c=geometry.Open()){c.BeginFigure(motionPath[0],false,false);c.PolyLineTo(motionPath, true, true);}geometry.Freeze();routeGeometry=geometry;
        }
        private void StartWave()
        {
            if(waveRunning)return;if(gameOver){ResetGame();return;}if(paused)TogglePause();
            if(stageReady){int refund=0;foreach(Tower t in towers)refund+=(int)(t.Invested*.55);goldCount+=refund+220;ClearTowerModels();towers.Clear();ClearEnemyModels();enemies.Clear();ClearBoltModels();bolts.Clear();selectedTower=null;selectedType=null;SetBuildGhost(null);lives=15;arenaIndex++;waveInArena=0;stageReady=false;SetArenaPath();UpdateStatus(arenaShort[Math.Min(arenaIndex,arenaShort.Length-1)]+" · получено "+(refund+220)+" золота за переход.");}
            waveInArena++;totalWaves++;waveRunning=true;remainingSpawns=6+waveInArena*2;spawnCountdown=.25;overlayBorder.Visibility=Visibility.Collapsed;pauseBorder.Visibility=Visibility.Collapsed;pauseButton.IsEnabled=true;startButton.IsEnabled=false;startButton.Content="Волна идёт…";RefreshHud();RefreshCards();UpdateSelection();surface.InvalidateVisual();
        }
        private void ResetGame(){goldCount=360;lives=15;totalWaves=0;waveInArena=0;arenaIndex=0;stageReady=false;gameOver=false;waveRunning=false;paused=false;pauseBorder.Visibility=Visibility.Collapsed;pauseButton.IsEnabled=false;pauseButton.Content="Ⅱ Пауза";remainingSpawns=0;ClearEnemyModels();enemies.Clear();ClearTowerModels();towers.Clear();ClearBoltModels();bolts.Clear();bursts.Clear();selectedType=null;selectedTower=null;SetBuildGhost(null);SetArenaPath();startButton.Content="▶  Начать волну";startButton.IsEnabled=true;overlayHeading.Text="Держи рубеж!";overlayBody.Text="Расставь магов рядом с дорогой и пройди кампанию из 18 арен по 15 волн.";overlayBorder.Visibility=Visibility.Collapsed;RefreshHud();RefreshCards();UpdateSelection();surface.InvalidateVisual();}
        private void TogglePause(){if(totalWaves==0||gameOver)return;paused=!paused;pauseBorder.Visibility=paused?Visibility.Visible:Visibility.Collapsed;pauseButton.Content=paused?"▶ Продолжить":"Ⅱ Пауза";UpdateStatus(paused?"Игра на паузе.":"Игра продолжается.");surface.InvalidateVisual();}
        private void Spawn()
        {
            int ordinal=remainingSpawns--;string kind;if(waveInArena<3)kind=ordinal%2==0?"goblin":"orc";else if(waveInArena<6)kind=ordinal%3==0?"warg":"uruk";else if(waveInArena<10)kind=ordinal%4==0?"troll":"uruk";else kind=ordinal%5==0?"nazgul":ordinal%3==0?"troll":"uruk";
            bool boss=ordinal==0&&waveInArena%5==0;if(boss)kind=waveInArena>=WavesPerArena?"nazgul":"troll";int k=Array.IndexOf(enemyIds,kind);double hp=36+waveInArena*18+arenaIndex*55+(boss?145:0),speed=kind=="warg"?82:kind=="troll"?31:kind=="nazgul"?61:kind=="goblin"?62:49;int[] reward={20,24,30,34,42,54};int r=reward[k];if(boss)r=100+arenaIndex*30+waveInArena*4;else r=(int)Math.Round(r*(1+arenaIndex*.15+waveInArena*.035));Enemy e=new Enemy{Kind=kind,Name=enemyNames[k],Distance=0,Speed=(speed+Math.Min(waveInArena,18)+arenaIndex*2)*MapScale,Hp=hp,MaxHp=hp,Reward=r,Radius=((kind=="troll"||kind=="nazgul")?19:kind=="uruk"?15:12)*MapScale,Boss=boss,Phase=gameplayRandom.NextDouble()*6};enemies.Add(e);PositionEnemy(e);e.Model=TakeEnemyModel(e.Kind);if(e.Model!=null&&worldView!=null)worldView.Children.Add(e.Model.Visual);
        }
        private void StartEnemyModelPrewarm()
        {
            if(enemyPrewarmTimer!=null)return;enemyPrewarmTimer=new DispatcherTimer(DispatcherPriority.Background);enemyPrewarmTimer.Interval=TimeSpan.FromMilliseconds(90);enemyPrewarmTimer.Tick+=delegate{if(enemyPrewarmIndex>=8){enemyPrewarmTimer.Stop();return;}string kind=enemyPrewarmIndex<4?(enemyPrewarmIndex<2?"goblin":"orc"):enemyIds[enemyPrewarmIndex-2];Queue<EnemyRig3D> pool;if(!enemyModelPool.TryGetValue(kind,out pool)){pool=new Queue<EnemyRig3D>();enemyModelPool.Add(kind,pool);}pool.Enqueue(CreateEnemyModel(kind));enemyPrewarmIndex++;};enemyPrewarmTimer.Start();
        }
        private EnemyRig3D TakeEnemyModel(string kind){Queue<EnemyRig3D> pool;if(enemyModelPool.TryGetValue(kind,out pool)&&pool.Count>0)return pool.Dequeue();return CreateEnemyModel(kind);}
        private void TickGame(double dt)
        {
            clock+=dt;
            if(waveRunning){spawnCountdown-=dt;if(spawnCountdown<=0&&remainingSpawns>0){Spawn();spawnCountdown=Math.Max(.38,1.02-waveInArena*.025);}
                for(int i=enemies.Count-1;i>=0;i--){Enemy e=enemies[i];double slow=e.SlowUntil>clock?e.Slow:1;e.Distance+=e.Speed*slow*dt;PositionEnemy(e);if(e.Distance>=routeLength){RemoveEnemyModel(e);enemies.RemoveAt(i);lives--;RefreshHud();UpdateStatus(e.Name+" прорвался к рубежу!");if(lives<=0){waveRunning=false;gameOver=true;paused=false;pauseBorder.Visibility=Visibility.Collapsed;pauseButton.IsEnabled=false;startButton.IsEnabled=true;startButton.Content="Начать заново";overlayHeading.Text="Рубеж пал";overlayBody.Text="Перестрой оборону и попробуй ещё раз.";overlayBorder.Visibility=Visibility.Visible;}}}
                if(remainingSpawns<=0&&enemies.Count==0){waveRunning=false;int bonus=80+arenaIndex*25+waveInArena*5;goldCount+=bonus;startButton.IsEnabled=true;if(waveInArena>=WavesPerArena){if(arenaIndex>=ArenaCount-1){gameOver=true;startButton.Content="Начать кампанию заново";overlayHeading.Text="Средиземье спасено!";overlayBody.Text="Все 18 арен и 270 волн пройдены. Нажми кнопку, чтобы начать заново.";overlayBorder.Visibility=Visibility.Visible;}else{stageReady=true;startButton.Content="Перейти на арену "+(arenaIndex+2);overlayHeading.Text="Рубеж удержан!";overlayBody.Text="15 волн отбиты. Следующая карта станет больше, а дорога — длиннее.";overlayBorder.Visibility=Visibility.Visible;}}else startButton.Content="▶  Начать волну "+(waveInArena+1)+"/"+WavesPerArena;UpdateStatus("Волна отбита · награда +"+bonus+" золота.");RefreshHud();RefreshCards();}}
            foreach(Tower t in towers){if(t.Type.Id=="aura")continue;t.Cooldown-=dt;if(t.Cooldown<=0){double dm,sp;Buff(t,out dm,out sp);int n=t.Type.Id=="gondor"&&t.Level>=4?3:1;List<Enemy> targets=new List<Enemy>(n);foreach(Enemy candidate in enemies){if(Distance(t.X,t.Y,candidate.X,candidate.Y)>t.Range)continue;int insert=0;while(insert<targets.Count&&targets[insert].Distance>=candidate.Distance)insert++;if(insert<n){targets.Insert(insert,candidate);if(targets.Count>n)targets.RemoveAt(targets.Count-1);}}if(targets.Count>0){t.LastShot=clock;t.LastTargetX=targets[0].X;t.LastTargetY=targets[0].Y;audio.PlayTower(t.Type.Id);for(int j=0;j<targets.Count;j++){Bolt p=new Bolt{Source=t,Target=targets[j],X=t.X+9*MapScale,Y=t.Y-22*MapScale,Damage=t.Damage*dm,Speed=440*MapScale,Type=t.Type.Id,Phase=clock*2.7+j*1.8,Slow=t.Type.Id=="ice"?(t.Level>=4?.12:.55):1,SlowTime=t.Type.Id=="ice"?1.5:0,Freeze=t.Type.Id=="ice"&&t.Level>=4?.7:0,Splash=t.Level>=4&&t.Type.Id=="dwarf"?52*MapScale:0,Pierce=t.Level>=4&&t.Type.Id=="elf"?3:0};bolts.Add(p);p.Model=CreateBoltModel(p.Type);if(p.Model!=null&&worldView!=null)worldView.Children.Add(p.Model.Visual);}t.Cooldown=t.Rate/sp;}}}
            for(int i=bolts.Count-1;i>=0;i--){Bolt b=bolts[i];if(b.Target==null||!enemies.Contains(b.Target)){RemoveBoltModel(b);bolts.RemoveAt(i);continue;}double dx=b.Target.X-b.X,dy=b.Target.Y-b.Y,d=Math.Sqrt(dx*dx+dy*dy),step=b.Speed*dt;if(d<=step+b.Target.Radius){Impact(b,b.Target);if(b.Target==null){RemoveBoltModel(b);bolts.RemoveAt(i);}}else{b.X+=dx/d*step;b.Y+=dy/d*step;}}
            for(int i=bursts.Count-1;i>=0;i--){bursts[i].Life+=dt;if(bursts[i].Life>=bursts[i].Duration)bursts.RemoveAt(i);}if(selectedTower!=null&&!towers.Contains(selectedTower)){selectedTower=null;UpdateSelection();}
        }
        private void PositionEnemy(Enemy e){if(motionPath.Length<2)return;int i=Math.Max(0,Math.Min(e.PathSegment,motionPath.Length-2));while(i<motionPath.Length-2&&e.Distance>motionDistances[i+1])i++;e.PathSegment=i;Point a=motionPath[i],b=motionPath[i+1];double len=motionDistances[i+1]-motionDistances[i],u=len<=0?0:(e.Distance-motionDistances[i])/len;u=Math.Max(0,Math.Min(1,u));e.X=a.X+(b.X-a.X)*u;e.Y=a.Y+(b.Y-a.Y)*u;}
        private static double Distance(Point a,Point b){double x=a.X-b.X,y=a.Y-b.Y;return Math.Sqrt(x*x+y*y);}
        private static double Distance(double x1,double y1,double x2,double y2){double x=x1-x2,y=y1-y2;return Math.Sqrt(x*x+y*y);}
        private void Impact(Bolt b,Enemy e){if(!enemies.Contains(e)||!b.Hit.Add(e))return;e.Hp-=b.Damage;if(b.Slow<1){e.Slow=Math.Min(e.Slow,b.Slow);e.SlowUntil=clock+b.SlowTime;}if(b.Freeze>0){e.Slow=.04;e.SlowUntil=clock+b.Freeze;}bursts.Add(new Burst{X=e.X,Y=e.Y,Life=0,Duration=.24,Color=TypeColor(b.Type,b.Source.Level)});if(e.Hp<=0)Defeat(e);if(b.Splash>0){Enemy[] copy=enemies.ToArray();foreach(Enemy other in copy)if(other!=e&&Distance(other.X,other.Y,e.X,e.Y)<b.Splash){other.Hp-=b.Damage*.55;if(other.Hp<=0)Defeat(other);}}if(b.Pierce>0){b.Pierce--;b.Target=null;Enemy next=null;double best=double.MaxValue;foreach(Enemy other in enemies)if(!b.Hit.Contains(other)&&Distance(other.X,other.Y,b.X,b.Y)<90&&other.Distance<best){next=other;best=other.Distance;}if(next!=null)b.Target=next;}else b.Target=null;}
        private void Defeat(Enemy e){if(!enemies.Remove(e))return;RemoveEnemyModel(e);audio.PlayDeath(e.Kind);goldCount+=e.Reward;bursts.Add(new Burst{X=e.X,Y=e.Y,Life=0,Duration=.38,Color=Color.FromRgb(241,201,110)});RefreshHud();RefreshCards();UpdateStatus(e.Name+" повержен · +"+e.Reward+" золота.");}
        private void RemoveEnemyModel(Enemy e){if(e==null||e.Model==null)return;EnemyRig3D rig=e.Model;if(worldView!=null)worldView.Children.Remove(rig.Visual);Queue<EnemyRig3D> pool;if(!enemyModelPool.TryGetValue(e.Kind,out pool)){pool=new Queue<EnemyRig3D>();enemyModelPool.Add(e.Kind,pool);}pool.Enqueue(rig);e.Model=null;}
        private void ClearEnemyModels(){if(enemies==null)return;foreach(Enemy e in enemies)RemoveEnemyModel(e);}
        private void Buff(Tower t,out double damage,out double speed){damage=1;speed=1;foreach(Tower a in towers){if(a==t||a.Type.Id!="aura"||Distance(a.X,a.Y,t.X,t.Y)>a.Range)continue;if(a.Aura=="damage")damage*=1+a.Power;else speed*=1+a.Power;}}
        private void Upgrade(){if(selectedTower==null||selectedTower.Level>=4)return;Tower t=selectedTower;HeroType d=t.Type;int cost=d.UpgradeCosts[t.Level];if(goldCount<cost)return;goldCount-=cost;t.Invested+=cost;t.Level++;if(d.Id=="aura"){t.Range+=28*MapScale;t.Power=new[]{.3,.4,.52,.66,.82}[t.Level];}else{t.Damage*=d.Id=="gondor"?1.34:1.4;t.Range+=16*MapScale;t.Rate*=d.Id=="gondor"?.82:.9;}RebuildTowerModel(t);RefreshHud();RefreshCards();UpdateSelection();surface.InvalidateVisual();UpdateStatus(d.Forms[t.Level]+" · улучшение завершено.");}
        private void Sell(){if(selectedTower==null)return;int refund=selectedTower.Invested;RemoveTowerModel(selectedTower);towers.Remove(selectedTower);selectedTower=null;goldCount+=refund;RefreshHud();RefreshCards();UpdateSelection();surface.InvalidateVisual();UpdateStatus("Маг снят с позиции · возвращено "+refund+" золота.");}
        private void SetAura(string mode){if(selectedTower==null||selectedTower.Type.Id!="aura")return;selectedTower.Aura=mode;UpdateSelection();surface.InvalidateVisual();UpdateStatus("Аура выбрана: "+(mode=="damage"?"урон":"скорость атаки")+".");}
        private static Color TypeColor(string id,int level){Color[] colors=id=="gondor"?new[]{Color.FromRgb(225,91,56),Color.FromRgb(255,167,73)}:id=="elf"?new[]{Color.FromRgb(106,221,144),Color.FromRgb(148,243,197)}:id=="dwarf"?new[]{Color.FromRgb(240,104,41),Color.FromRgb(255,209,81)}:id=="ice"?new[]{Color.FromRgb(100,217,255),Color.FromRgb(209,250,255)}:new[]{Color.FromRgb(237,103,163),Color.FromRgb(255,190,221)};return colors[Math.Min(level>=4?1:0,1)];}
        internal Point ScreenToWorld(Point p,double width,double height){double scale=Math.Min(width/WorldW,height/WorldH)*Zoom;if(scale<=0)return new Point(-100,-100);double ox=width*.5-viewCenterX*scale,oy=height*.5-viewCenterY*scale;return new Point((p.X-ox)/scale,(p.Y-oy)/scale);}
        private void ChangeZoom(int delta){if(surface==null)return;ZoomBy(delta,new Point(surface.ActualWidth*.5,surface.ActualHeight*.5),surface.ActualWidth,surface.ActualHeight);}
        internal void ZoomBy(int delta,Point pointer,double width,double height)
        {
            if(width<1||height<1||delta==0)return;Point anchor=ScreenToWorld(pointer,width,height);double requested=Math.Max(.65,Math.Min(2.75,targetZoom*Math.Pow(1.14,delta/120.0)));if(Math.Abs(requested-targetZoom)<.001)return;double factor=requested/Zoom;targetZoom=requested;targetCenterX=anchor.X-(anchor.X-viewCenterX)/factor;targetCenterY=anchor.Y-(anchor.Y-viewCenterY)/factor;double baseScale=Math.Min(width/WorldW,height/WorldH),visibleW=width/(baseScale*targetZoom),visibleH=height/(baseScale*targetZoom);targetCenterX=visibleW>=WorldW?WorldW*.5:Math.Max(visibleW*.5,Math.Min(WorldW-visibleW*.5,targetCenterX));targetCenterY=visibleH>=WorldH?WorldH*.5:Math.Max(visibleH*.5,Math.Min(WorldH-visibleH*.5,targetCenterY));if(zoomLabel!=null)zoomLabel.Text=Math.Round(targetZoom*100)+"%";if(surface!=null)surface.InvalidateVisual();UpdateStatus("Масштаб карты · "+Math.Round(targetZoom*100)+"% · колесо мыши меняет масштаб.");
        }
        private bool AdvanceZoom(double dt)
        {
            double blend=1-Math.Exp(-Math.Max(.001,dt)*13);double zoomDelta=targetZoom-Zoom,xDelta=targetCenterX-viewCenterX,yDelta=targetCenterY-viewCenterY;if(Math.Abs(zoomDelta)<.0004&&Math.Abs(xDelta)<.03&&Math.Abs(yDelta)<.03){Zoom=targetZoom;viewCenterX=targetCenterX;viewCenterY=targetCenterY;return false;}Zoom+=zoomDelta*blend;viewCenterX+=xDelta*blend;viewCenterY+=yDelta*blend;return true;
        }
        internal void UpdatePointer(Point p){mouseWorld=p;if(selectedType!=null){UpdateBuildGhost();surface.InvalidateVisual();}}
        internal void PointerExit(){mouseWorld=new Point(-100,-100);UpdateBuildGhost();if(surface!=null)surface.InvalidateVisual();}
        internal void HandleFieldClick(Point p){for(int i=towers.Count-1;i>=0;i--)if(Distance(towers[i].X,towers[i].Y,p.X,p.Y)<35*MapScale){selectedTower=towers[i];selectedType=null;SetBuildGhost(null);RefreshCards();UpdateSelection();surface.InvalidateVisual();return;}if(selectedType!=null){Place(p.X,p.Y);return;}selectedTower=null;UpdateSelection();surface.InvalidateVisual();}
        internal void HandleFieldRightClick(){if(selectedType==null&&selectedTower==null)return;selectedType=null;selectedTower=null;SetBuildGhost(null);RefreshCards();UpdateSelection();surface.InvalidateVisual();UpdateStatus("Выбор снят.");}
        private bool NearPath(double x,double y){for(int i=1;i<motionPath.Length;i++)if(PointSegmentDistance(x,y,motionPath[i-1],motionPath[i])<48*MapScale)return true;return false;}
        private static double PointSegmentDistance(double x,double y,Point a,Point b){double dx=b.X-a.X,dy=b.Y-a.Y,l=dx*dx+dy*dy,t=l==0?0:Math.Max(0,Math.Min(1,((x-a.X)*dx+(y-a.Y)*dy)/l));return Distance(x,y,a.X+t*dx,a.Y+t*dy);}
        private bool ValidSpot(double x,double y){double margin=36*MapScale;if(x<margin||x>WorldW-margin||y<margin||y>WorldH-margin||NearPath(x,y))return false;foreach(Tower t in towers)if(Distance(x,y,t.X,t.Y)<54*MapScale)return false;return true;}
        private void Place(double x,double y){if(selectedType==null)return;if(goldCount<selectedType.Price){UpdateStatus("Не хватает золота.");return;}if(!ValidSpot(x,y)){UpdateStatus("Красное место — слишком близко к дороге или другому магу.");return;}Tower t=new Tower{Type=selectedType,X=x,Y=y,Damage=selectedType.Damage,Range=selectedType.Range*MapScale,Rate=selectedType.Rate,Invested=selectedType.Price};towers.Add(t);t.Model=CreateTowerModel(t);if(t.Model!=null&&worldView!=null)worldView.Children.Add(t.Model.Visual);goldCount-=selectedType.Price;selectedTower=t;selectedType=null;SetBuildGhost(null);RefreshHud();RefreshCards();UpdateSelection();UpdateStatus("Маг занял позицию. Развивай его по мере волн.");surface.InvalidateVisual();}

        private void ConfigureWorldCamera(double width,double height)
        {
            if(worldCamera==null||width<1||height<1)return;double aspect=width/height,viewW=Math.Max(WorldW,WorldH*aspect)/Zoom,elev=.53,up=Math.Sqrt(1-elev*elev),depth=WorldH/elev,distance=5000;
            if(Math.Abs(viewW-cameraViewWidth)<.01&&Math.Abs(height-cameraViewHeight)<.01&&Math.Abs(WorldW-cameraWorldW)<.01&&Math.Abs(WorldH-cameraWorldH)<.01&&Math.Abs(viewCenterX-cameraCenterX)<.01&&Math.Abs(viewCenterY-cameraCenterY)<.01)return;
            groundDepthScale=1/elev;worldCamera.Position=new Point3D(viewCenterX,distance*elev,viewCenterY*groundDepthScale+distance*up);worldCamera.LookDirection=new Vector3D(0,-elev,-up);worldCamera.UpDirection=new Vector3D(0,up,-elev);worldCamera.Width=viewW;worldCamera.NearPlaneDistance=1;worldCamera.FarPlaneDistance=distance+Math.Max(WorldW,depth)*2;cameraViewWidth=viewW;cameraViewHeight=height;cameraWorldW=WorldW;cameraWorldH=WorldH;cameraCenterX=viewCenterX;cameraCenterY=viewCenterY;
        }
        private Model3D BuildWorldGround(BitmapSource textureImage)
        {
            ClearAmbientCritters();Model3DGroup world=new Model3DGroup();MeshGeometry3D terrain=BuildTerrainMesh();ImageBrush texture=new ImageBrush(textureImage){Stretch=Stretch.Fill,TileMode=TileMode.Tile};texture.Freeze();MaterialGroup groundMaterial=new MaterialGroup();groundMaterial.Children.Add(new DiffuseMaterial(texture));groundMaterial.Children.Add(new SpecularMaterial(Frozen(Color.FromArgb(30,205,207,177)),8));groundMaterial.Freeze();GeometryModel3D ground=new GeometryModel3D(terrain,groundMaterial){BackMaterial=groundMaterial};ground.Freeze();world.Children.Add(ground);AddRoadGeometry(world,arenaIndex);AddTerrainModels(world,arenaIndex);AddCaveGates3D(world,arenaIndex);BatchStaticGeometry(world);world.Freeze();BuildAmbientCritters(arenaIndex);return world;
        }
        private void BatchStaticGeometry(Model3DGroup world)
        {
            Dictionary<Tuple<Material,Material>,MeshGeometry3D> batches=new Dictionary<Tuple<Material,Material>,MeshGeometry3D>();List<Model3D> keep=new List<Model3D>();
            foreach(Model3D item in world.Children)
            {
                GeometryModel3D model=item as GeometryModel3D;MeshGeometry3D source=model==null?null:model.Geometry as MeshGeometry3D;if(source==null){keep.Add(item);continue;}
                Tuple<Material,Material> key=Tuple.Create(model.Material,model.BackMaterial);MeshGeometry3D target;if(!batches.TryGetValue(key,out target)){target=new MeshGeometry3D();batches.Add(key,target);}
                Matrix3D transform=model.Transform==null?Matrix3D.Identity:model.Transform.Value,normalTransform=Matrix3D.Identity;if(transform.HasInverse){Matrix3D inverse=transform;inverse.Invert();normalTransform=new Matrix3D(inverse.M11,inverse.M21,inverse.M31,0,inverse.M12,inverse.M22,inverse.M32,0,inverse.M13,inverse.M23,inverse.M33,0,0,0,0,1);}
                int offset=target.Positions.Count;for(int i=0;i<source.Positions.Count;i++){target.Positions.Add(transform.Transform(source.Positions[i]));Vector3D normal=i<source.Normals.Count?source.Normals[i]:new Vector3D(0,1,0);normal=normalTransform.Transform(normal);if(normal.LengthSquared>.000001)normal.Normalize();target.Normals.Add(normal);target.TextureCoordinates.Add(i<source.TextureCoordinates.Count?source.TextureCoordinates[i]:new Point(0,0));}foreach(int index in source.TriangleIndices)target.TriangleIndices.Add(offset+index);
            }
            world.Children.Clear();foreach(Model3D item in keep)world.Children.Add(item);foreach(KeyValuePair<Tuple<Material,Material>,MeshGeometry3D> batch in batches){if(batch.Value.Positions.Count==0)continue;batch.Value.Freeze();GeometryModel3D merged=new GeometryModel3D(batch.Value,batch.Key.Item1){BackMaterial=batch.Key.Item2};merged.Freeze();world.Children.Add(merged);}
        }
        private void ClearAmbientCritters()
        {
            if(worldView!=null){foreach(AmbientCritterRig3D rig in ambientCritters)if(rig.Visual!=null)worldView.Children.Remove(rig.Visual);foreach(BirdRig3D bird in birds)if(bird.Visual!=null)worldView.Children.Remove(bird.Visual);}ambientCritters.Clear();birds.Clear();
        }
        private void BuildAmbientCritters(int scene)
        {
            if(worldView==null)return;Random random=new Random(29011+scene*79);int made=0;for(int attempt=0;attempt<80&&made<3;attempt++){double x=(.15+random.NextDouble()*.70)*WorldW,y=(.15+random.NextDouble()*.70)*WorldH;if(NearPath(x,y,165*MapScale))continue;AmbientCritterRig3D rig=CreateAmbientLizard(x,y,14.5*MapScale,(made*2.17)+random.NextDouble()*3.14);ambientCritters.Add(rig);worldView.Children.Add(rig.Visual);made++;}for(int i=0;i<4;i++){double x=(.18+random.NextDouble()*.64)*WorldW,y=(.18+random.NextDouble()*.64)*WorldH;BirdRig3D bird=CreateBird(x,y,9.2*MapScale,(88+random.NextDouble()*54)*MapScale,i*1.71+random.NextDouble()*3.14,.25+random.NextDouble()*.20,scene);birds.Add(bird);worldView.Children.Add(bird.Visual);}
        }
        private BirdRig3D CreateBird(double x,double y,double size,double height,double phase,double speed,int scene)
        {
            BirdRig3D rig=new BirdRig3D{X=x,Y=y,Range=84*MapScale,Height=height,Phase=phase,Speed=speed};Color bodyColor=scene%3==2?Color.FromRgb(195,211,210):scene%3==1?Color.FromRgb(93,64,47):Color.FromRgb(48,69,54),wingColor=scene%3==2?Color.FromRgb(115,149,156):scene%3==1?Color.FromRgb(151,105,67):Color.FromRgb(90,119,76);Model3DGroup creature=new Model3DGroup();rig.Yaw=new AxisAngleRotation3D(new Vector3D(0,1,0),0);creature.Transform=new RotateTransform3D(rig.Yaw);AddEllipsoid(creature,new Point3D(0,0,0),new Vector3D(.61,.17,.27),bodyColor);AddEllipsoid(creature,new Point3D(.48,.09,0),new Vector3D(.24,.20,.20),bodyColor);AddCone(creature,new Point3D(.66,.06,0),new Point3D(.97,.015,0),.09,Color.FromRgb(196,153,83));AddCone(creature,new Point3D(-.42,.04,0),new Point3D(-.87,-.02,0),.11,wingColor);
            rig.LeftWing=new AxisAngleRotation3D(new Vector3D(1,0,0),0);rig.RightWing=new AxisAngleRotation3D(new Vector3D(1,0,0),0);Model3DGroup left=new Model3DGroup(),right=new Model3DGroup();left.Transform=new RotateTransform3D(rig.LeftWing,new Point3D(-.03,.04,.10));right.Transform=new RotateTransform3D(rig.RightWing,new Point3D(-.03,.04,-.10));AddCone(left,new Point3D(-.03,.04,.10),new Point3D(-.18,.04,.92),.19,wingColor);AddCone(right,new Point3D(-.03,.04,-.10),new Point3D(-.18,.04,-.92),.19,wingColor);for(int i=0;i<4;i++){double z=.35+i*.13;AddCone(left,new Point3D(-.09,.035,z),new Point3D(-.31-i*.08,.02,z+.20),.075,bodyColor);AddCone(right,new Point3D(-.09,.035,-z),new Point3D(-.31-i*.08,.02,-z-.20),.075,bodyColor);}creature.Children.Add(left);creature.Children.Add(right);
            Model3DGroup rootModel=new Model3DGroup();rootModel.Children.Add(creature);rig.Position=new TranslateTransform3D(x,TerrainHeight(x,y)+height,y*groundDepthScale);rig.Scale=new ScaleTransform3D(size,size,size);Transform3DGroup worldTransform=new Transform3DGroup();worldTransform.Children.Add(rig.Scale);worldTransform.Children.Add(rig.Position);rig.Visual=new ModelVisual3D{Content=rootModel,Transform=worldTransform};return rig;
        }
        private AmbientCritterRig3D CreateAmbientLizard(double x,double y,double size,double phase)
        {
            AmbientCritterRig3D rig=new AmbientCritterRig3D{X=x,Y=y,Range=.43,Phase=phase,Scale=size};Model3DGroup scene=new Model3DGroup();
            AddEllipsoid(scene,new Point3D(0,.16,0),new Vector3D(1.30,.30,1.03*groundDepthScale),Color.FromRgb(53,63,48));AddEllipsoid(scene,new Point3D(-.08,.33,-.04),new Vector3D(.96,.33,.76*groundDepthScale),Color.FromRgb(105,123,76));AddEllipsoid(scene,new Point3D(-.19,.48,-.08),new Vector3D(.59,.17,.47*groundDepthScale),Color.FromRgb(126,143,86));AddEllipsoid(scene,new Point3D(-.39,.565,-.07),new Vector3D(.33,.055,.28*groundDepthScale),Color.FromRgb(167,164,103));
            Model3DGroup creature=new Model3DGroup();rig.CreaturePosition=new TranslateTransform3D(0,.43*size,0);rig.CreatureYaw=new AxisAngleRotation3D(new Vector3D(0,1,0),0);rig.CreatureScale=new ScaleTransform3D(1,1,1);Transform3DGroup creatureTransform=new Transform3DGroup();creatureTransform.Children.Add(rig.CreatureScale);creatureTransform.Children.Add(new RotateTransform3D(rig.CreatureYaw));creatureTransform.Children.Add(rig.CreaturePosition);creature.Transform=creatureTransform;
            Color skin=Color.FromRgb(81,112,63),belly=Color.FromRgb(173,164,104),dark=Color.FromRgb(39,55,39),eye=Color.FromRgb(225,191,82);AddEllipsoid(creature,new Point3D(-.10,.49,0),new Vector3D(.55,.25,.33*groundDepthScale),skin);AddEllipsoid(creature,new Point3D(.40,.59,0),new Vector3D(.30,.22,.27*groundDepthScale),Color.FromRgb(105,132,74));AddEllipsoid(creature,new Point3D(.65,.51,0),new Vector3D(.26,.105,.20*groundDepthScale),skin);AddEllipsoid(creature,new Point3D(-.06,.33,.01),new Vector3D(.39,.10,.23*groundDepthScale),belly);
            for(int side=-1;side<=1;side+=2){AddEllipsoid(creature,new Point3D(.48,.70,side*.19*groundDepthScale),new Vector3D(.105,.09,.09*groundDepthScale),Color.FromRgb(135,156,83));AddEllipsoid(creature,new Point3D(.505,.715,side*.245*groundDepthScale),new Vector3D(.061,.061,.044*groundDepthScale),Color.FromRgb(239,211,122));AddEllipsoid(creature,new Point3D(.535,.715,side*.273*groundDepthScale),new Vector3D(.025,.045,.020*groundDepthScale),Color.FromRgb(25,31,23));AddCone(creature,new Point3D(.63,.575,side*.13*groundDepthScale),new Point3D(.93,.535,side*.12*groundDepthScale),.07,Color.FromRgb(115,137,79));}
            for(int i=0;i<6;i++){double px=-.39+i*.17;AddEllipsoid(creature,new Point3D(px,.685,0),new Vector3D(.050,.022,.056*groundDepthScale),i%2==0?Color.FromRgb(188,174,103):dark);}
            rig.FrontLeft=NewRigRotation();rig.FrontRight=NewRigRotation();rig.BackLeft=NewRigRotation();rig.BackRight=NewRigRotation();AddLizardLeg(creature,rig.FrontLeft,.27,-1,skin,dark);AddLizardLeg(creature,rig.FrontRight, .27,1,skin,dark);AddLizardLeg(creature,rig.BackLeft,-.39,-1,skin,dark);AddLizardLeg(creature,rig.BackRight,-.39,1,skin,dark);
            Model3DGroup tail=new Model3DGroup();rig.Tail=new AxisAngleRotation3D(new Vector3D(0,1,0),0);tail.Transform=new RotateTransform3D(rig.Tail,new Point3D(-.48,.48,0));AddCone(tail,new Point3D(-.42,.49,0),new Point3D(-.82,.43,0),.18,skin);AddCone(tail,new Point3D(-.78,.43,0),new Point3D(-1.17,.32,0),.125,Color.FromRgb(78,108,60));AddCone(tail,new Point3D(-1.12,.32,0),new Point3D(-1.43,.19,0),.072,Color.FromRgb(61,91,52));creature.Children.Add(tail);scene.Children.Add(creature);
            rig.WorldPosition=new TranslateTransform3D(x,TerrainHeight(x,y),y*groundDepthScale);rig.WorldScale=new ScaleTransform3D(size,size,size);Transform3DGroup worldTransform=new Transform3DGroup();worldTransform.Children.Add(rig.WorldScale);worldTransform.Children.Add(rig.WorldPosition);rig.Visual=new ModelVisual3D{Content=scene,Transform=worldTransform};return rig;
        }
        private void AddLizardLeg(Model3DGroup root,AxisAngleRotation3D rotation,double x,int side,Color skin,Color dark)
        {
            double z=side*.27*groundDepthScale;Model3DGroup leg=new Model3DGroup();leg.Transform=new RotateTransform3D(rotation,new Point3D(x,.48,z));AddEllipsoid(leg,new Point3D(x+.015,.34,z+side*.035*groundDepthScale),new Vector3D(.15,.22,.12*groundDepthScale),skin);AddEllipsoid(leg,new Point3D(x+.12,.18,z+side*.06*groundDepthScale),new Vector3D(.13,.095,.14*groundDepthScale),dark);for(int i=0;i<3;i++)AddCone(leg,new Point3D(x+.19,.16,z+side*.06*groundDepthScale+(i-1)*.045*groundDepthScale),new Point3D(x+.30,.13,z+side*.06*groundDepthScale+(i-1)*.065*groundDepthScale),.026,skin);root.Children.Add(leg);
        }
        private void UpdateAmbientCritters()
        {
            foreach(AmbientCritterRig3D rig in ambientCritters){double a=clock*.9+rig.Phase,x=Math.Sin(a)*rig.Range,z=Math.Cos(a)*rig.Range*.54,dx=Math.Cos(a),dz=-Math.Sin(a)*.54,cycle=clock*14+rig.Phase,stride=Math.Sin(cycle);rig.CreaturePosition.OffsetX=x*rig.Scale;rig.CreaturePosition.OffsetZ=z*rig.Scale;rig.CreatureYaw.Angle=-Math.Atan2(dz,dx)*180/Math.PI;rig.WorldPosition.OffsetY=TerrainHeight(rig.X,rig.Y);if(rig.FrontLeft!=null)rig.FrontLeft.Angle=stride*36;if(rig.FrontRight!=null)rig.FrontRight.Angle=-stride*36;if(rig.BackLeft!=null)rig.BackLeft.Angle=-stride*31;if(rig.BackRight!=null)rig.BackRight.Angle=stride*31;if(rig.Tail!=null)rig.Tail.Angle=Math.Sin(clock*5+rig.Phase)*18;rig.CreaturePosition.OffsetY=(.43+Math.Abs(stride)*.025)*rig.Scale;}
            foreach(BirdRig3D bird in birds){double a=clock*bird.Speed+bird.Phase,x=bird.X+Math.Cos(a)*bird.Range,y=bird.Y+Math.Sin(a*.72)*bird.Range*.46,dx=-Math.Sin(a)*bird.Speed,dy=Math.Cos(a*.72)*.72*bird.Speed;bird.Position.OffsetX=x;bird.Position.OffsetY=TerrainHeight(x,y)+bird.Height+Math.Sin(a*2)*3*MapScale;bird.Position.OffsetZ=y*groundDepthScale;bird.Yaw.Angle=-Math.Atan2(dy,dx)*180/Math.PI;double flap=Math.Sin(clock*14+bird.Phase)*38;bird.LeftWing.Angle=flap;bird.RightWing.Angle=-flap;}
        }
        private double TerrainHeight(double x,double y)
        {
            double sx=x/MapScale,sy=y/MapScale;double broad=Math.Sin(sx*.0047+Math.Sin(sy*.0031)*.8)*Math.Cos(sy*.0052-sx*.0014);double rolling=Math.Sin(sx*.012+sy*.007)*.45+Math.Cos(sy*.014-sx*.009)*.38;double small=Math.Sin(sx*.032+sy*.025)*.16+Math.Cos(sx*.027-sy*.041)*.12;double ridge=Math.Sin(sx*.0021+Math.Sin(sy*.0027)*.65)*Math.Cos(sy*.0024-sx*.0013);return (broad*17+rolling*7.2+small*2.1+ridge*4.5)*MapScale;
        }
        private MeshGeometry3D BuildTerrainMesh()
        {
            const int columns=160,rows=104;MeshGeometry3D mesh=new MeshGeometry3D();double dx=WorldW/columns,dy=WorldH/rows;
            for(int row=0;row<=rows;row++)for(int col=0;col<=columns;col++){double x=col*dx,y=row*dy,z=y*groundDepthScale,h=TerrainHeight(x,y);mesh.Positions.Add(new Point3D(x,h,z));Vector3D normal=new Vector3D(-(TerrainHeight(x+2,y)-TerrainHeight(x-2,y))/4,1,-(TerrainHeight(x,y+2)-TerrainHeight(x,y-2))/(4*groundDepthScale));normal.Normalize();mesh.Normals.Add(normal);mesh.TextureCoordinates.Add(new Point(x/(520*MapScale),y/(520*MapScale)));}
            for(int row=0;row<rows;row++)for(int col=0;col<columns;col++){int a=row*(columns+1)+col,b=a+1,c=a+columns+1,d=c+1;mesh.TriangleIndices.Add(a);mesh.TriangleIndices.Add(c);mesh.TriangleIndices.Add(b);mesh.TriangleIndices.Add(b);mesh.TriangleIndices.Add(c);mesh.TriangleIndices.Add(d);}mesh.Freeze();return mesh;
        }
        private void AddRoadGeometry(Model3DGroup world,int scene)
        {
            Color biome=scene%3==0?Color.FromRgb(75,61,43):scene%3==1?Color.FromRgb(89,64,45):Color.FromRgb(121,124,117);Material dark=Material3D(Color.FromRgb(43,37,30)),edge=Material3D(Color.FromRgb(105,86,58)),earth=Material3D(biome),stone=RoadStoneMaterial(scene);AddRoadRibbon(world,126*MapScale,0,dark);AddRoadRibbon(world,114*MapScale,1.0*MapScale,edge);AddRoadRibbon(world,103*MapScale,2.0*MapScale,earth);AddRoadRibbon(world,90*MapScale,2.8*MapScale,stone);AddRoadPebbles(world,scene);
        }
        private Material RoadStoneMaterial(int scene)
        {
            int size=256;DrawingGroup tile=new DrawingGroup();using(DrawingContext dc=tile.Open()){Color baseColor=scene%3==2?Color.FromRgb(179,177,158):Color.FromRgb(177,153,112);dc.DrawRectangle(Frozen(baseColor),null,new Rect(0,0,size,size));Random r=new Random(4601+scene);for(int i=0;i<430;i++){double x=r.NextDouble()*size,y=r.NextDouble()*size,w=1+r.NextDouble()*6,h=.5+r.NextDouble()*2;Color c=i%3==0?Color.FromArgb(72,77,57,40):Color.FromArgb(62,229,207,157);dc.DrawEllipse(Frozen(c),null,new Point(x,y),w,h);}for(int i=0;i<90;i++){double x=r.NextDouble()*size,y=r.NextDouble()*size,len=4+r.NextDouble()*13;dc.DrawLine(Stroke(Color.FromArgb(75,91,68,47),.7+r.NextDouble()),new Point(x,y),new Point(x+len,y+(r.NextDouble()-.5)*3));}}tile.Freeze();DrawingVisual visual=new DrawingVisual();using(DrawingContext dc=visual.RenderOpen())dc.DrawDrawing(tile);RenderTargetBitmap bitmap=new RenderTargetBitmap(size,size,96,96,PixelFormats.Pbgra32);bitmap.Render(visual);bitmap.Freeze();ImageBrush brush=new ImageBrush(bitmap){Stretch=Stretch.Fill,TileMode=TileMode.Tile};brush.Freeze();MaterialGroup material=new MaterialGroup();material.Children.Add(new DiffuseMaterial(brush));material.Children.Add(new SpecularMaterial(Frozen(Color.FromArgb(35,242,222,180)),7));material.Freeze();return material;
        }
        private void AddRoadRibbon(Model3DGroup world,double width,double lift,Material material)
        {
            if(motionPath==null||motionPath.Length<2)return;MeshGeometry3D mesh=new MeshGeometry3D();double distanceAlong=0;double[] cumulative=new double[motionPath.Length];for(int i=1;i<motionPath.Length;i++){distanceAlong+=Distance(motionPath[i-1],motionPath[i]);cumulative[i]=distanceAlong;}
            for(int i=0;i<motionPath.Length;i++){Point prev=motionPath[Math.Max(0,i-1)],next=motionPath[Math.Min(motionPath.Length-1,i+1)];double dx=next.X-prev.X,dy=next.Y-prev.Y,len=Math.Sqrt(dx*dx+dy*dy);if(len<.001)len=1;double nx=-dy/len,ny=dx/len;for(int side=-1;side<=1;side+=2){double x=motionPath[i].X+nx*side*width*.5,y=motionPath[i].Y+ny*side*width*.5,z=y*groundDepthScale;mesh.Positions.Add(new Point3D(x,TerrainHeight(x,y)+lift,z));mesh.Normals.Add(new Vector3D(0,1,0));mesh.TextureCoordinates.Add(new Point(cumulative[i]/(260*MapScale),side<0?0:1));}}
            for(int i=0;i<motionPath.Length-1;i++){int a=i*2;mesh.TriangleIndices.Add(a);mesh.TriangleIndices.Add(a+1);mesh.TriangleIndices.Add(a+2);mesh.TriangleIndices.Add(a+1);mesh.TriangleIndices.Add(a+3);mesh.TriangleIndices.Add(a+2);}mesh.Freeze();GeometryModel3D ribbon=new GeometryModel3D(mesh,material){BackMaterial=material};ribbon.Freeze();world.Children.Add(ribbon);
        }
        private void AddRoadPebbles(Model3DGroup world,int scene)
        {
            Random r=new Random(4221+scene*31);MeshGeometry3D mesh=new MeshGeometry3D();int count=(int)(145*MapScale);const int sides=6;for(int i=0;i<count;i++){int ix=r.Next(3,Math.Max(4,motionPath.Length-3));Point p=motionPath[ix],a=motionPath[ix-1],b=motionPath[ix+1];double dx=b.X-a.X,dy=b.Y-a.Y,len=Math.Sqrt(dx*dx+dy*dy);if(len<.001)continue;double side=r.Next(0,2)==0?-1:1,nx=-dy/len,ny=dx/len,offset=side*(35+r.NextDouble()*14)*MapScale,x=p.X+nx*offset,y=p.Y+ny*offset,z=y*groundDepthScale,h=TerrainHeight(x,y)+3.1*MapScale,s=(1.3+r.NextDouble()*2.5)*MapScale,ht=(.5+r.NextDouble()*1.1)*MapScale;int start=mesh.Positions.Count;for(int ring=0;ring<2;ring++)for(int j=0;j<sides;j++){double ang=2*Math.PI*j/sides,rr=s*(.78+r.NextDouble()*.22);mesh.Positions.Add(new Point3D(x+Math.Cos(ang)*rr,h+ring*ht,z+Math.Sin(ang)*rr*groundDepthScale));mesh.Normals.Add(new Vector3D(0,1,0));mesh.TextureCoordinates.Add(new Point(0,0));}for(int j=0;j<sides;j++){int a0=start+j,b0=start+(j+1)%sides,c0=start+sides+j,d0=start+sides+(j+1)%sides;mesh.TriangleIndices.Add(a0);mesh.TriangleIndices.Add(c0);mesh.TriangleIndices.Add(b0);mesh.TriangleIndices.Add(b0);mesh.TriangleIndices.Add(c0);mesh.TriangleIndices.Add(d0);}}
            if(mesh.Positions.Count==0)return;mesh.Freeze();GeometryModel3D stones=new GeometryModel3D(mesh,Material3D(scene%3==2?Color.FromRgb(188,188,169):Color.FromRgb(151,129,93))){BackMaterial=Material3D(scene%3==2?Color.FromRgb(188,188,169):Color.FromRgb(151,129,93))};stones.Freeze();world.Children.Add(stones);
        }
        private void AddTerrainModels(Model3DGroup world,int scene)
        {
            int biome=scene%3;Random r=new Random(8181+scene*43);int treeCount=(int)(46*MapScale*MapScale),rockCount=(int)(58*MapScale*MapScale),shrubCount=(int)(88*MapScale*MapScale);
            for(int i=0;i<treeCount;i++){double x=58*MapScale+r.NextDouble()*(WorldW-116*MapScale),y=55*MapScale+r.NextDouble()*(WorldH-110*MapScale);if(NearPath(x,y,100*MapScale))continue;double height=(54+r.NextDouble()*56)*MapScale;AddTree3D(world,x,y,height,biome,i);}
            for(int i=0;i<rockCount;i++){double x=40*MapScale+r.NextDouble()*(WorldW-80*MapScale),y=40*MapScale+r.NextDouble()*(WorldH-80*MapScale);if(NearPath(x,y,92*MapScale))continue;double radius=(13+r.NextDouble()*29)*MapScale;AddRock3D(world,x,y,radius,biome,i);}
            for(int i=0;i<shrubCount;i++){double x=32*MapScale+r.NextDouble()*(WorldW-64*MapScale),y=32*MapScale+r.NextDouble()*(WorldH-64*MapScale);if(NearPath(x,y,61*MapScale))continue;AddShrub3D(world,x,y,(8+r.NextDouble()*13)*MapScale,biome,i);}
            int logs=biome==1?34:26;for(int i=0;i<logs;i++){double x=30*MapScale+r.NextDouble()*(WorldW-60*MapScale),y=30*MapScale+r.NextDouble()*(WorldH-60*MapScale);if(NearPath(x,y,72*MapScale))continue;AddEllipsoid(world,new Point3D(x,TerrainHeight(x,y)+2*MapScale,y*groundDepthScale),new Vector3D((8+r.NextDouble()*17)*MapScale,(2.4+r.NextDouble()*3)*MapScale,(3+r.NextDouble()*4)*MapScale*groundDepthScale),biome==1?Color.FromRgb(70,48,32):Color.FromRgb(82,62,42));}AddGrass3D(world,scene);
        }
        private void AddGrass3D(Model3DGroup world,int scene)
        {
            int biome=scene%3;Color[][] palette={new[]{Color.FromRgb(40,83,43),Color.FromRgb(69,117,48),Color.FromRgb(103,139,58)},new[]{Color.FromRgb(111,73,45),Color.FromRgb(151,102,54),Color.FromRgb(184,127,69)},new[]{Color.FromRgb(75,111,113),Color.FromRgb(106,143,145),Color.FromRgb(156,177,168)}};MeshGeometry3D[] meshes={new MeshGeometry3D(),new MeshGeometry3D(),new MeshGeometry3D()};Random random=new Random(13731+scene*61);int clumps=(int)(220*MapScale*MapScale);
            for(int i=0;i<clumps;i++){double x=24*MapScale+random.NextDouble()*(WorldW-48*MapScale),y=24*MapScale+random.NextDouble()*(WorldH-48*MapScale);if(NearPath(x,y,67*MapScale))continue;double h=TerrainHeight(x,y),z=y*groundDepthScale;int blades=3+random.Next(3);for(int b=0;b<blades;b++){double angle=random.NextDouble()*Math.PI*2,height=(6+random.NextDouble()*10)*MapScale,width=(.8+random.NextDouble()*1.4)*MapScale,lean=(2+random.NextDouble()*5)*MapScale;AddGrassBlade(meshes[(i+b)%3],x+(random.NextDouble()-.5)*9*MapScale,h,z+(random.NextDouble()-.5)*9*MapScale,height,width,angle,lean);}}
            for(int i=0;i<meshes.Length;i++)if(meshes[i].Positions.Count>0){meshes[i].Freeze();Material material=Material3D(palette[biome][i]);GeometryModel3D cover=new GeometryModel3D(meshes[i],material){BackMaterial=material};cover.Freeze();world.Children.Add(cover);}
        }
        private void AddGrassBlade(MeshGeometry3D mesh,double x,double ground,double z,double height,double width,double angle,double lean)
        {
            double ax=-Math.Sin(angle),az=Math.Cos(angle),lx=Math.Cos(angle)*lean,lz=Math.Sin(angle)*lean*groundDepthScale;Point3D bl=new Point3D(x-ax*width*.5,ground,z-az*width*.5),br=new Point3D(x+ax*width*.5,ground,z+az*width*.5),ml=new Point3D(x+lx*.38-ax*width*.31,ground+height*.58,z+lz*.38-az*width*.31),mr=new Point3D(x+lx*.38+ax*width*.31,ground+height*.58,z+lz*.38+az*width*.31),tip=new Point3D(x+lx,ground+height,z+lz);AddGrassTriangle(mesh,bl,br,mr);AddGrassTriangle(mesh,bl,mr,ml);AddGrassTriangle(mesh,ml,mr,tip);
        }
        private static void AddGrassTriangle(MeshGeometry3D mesh,Point3D a,Point3D b,Point3D c)
        {
            Vector3D normal=Vector3D.CrossProduct(b-a,c-a);if(normal.LengthSquared<.000001)normal=new Vector3D(0,0,1);normal.Normalize();Point3D[] points={a,b,c};for(int i=0;i<3;i++){mesh.Positions.Add(points[i]);mesh.Normals.Add(normal);mesh.TextureCoordinates.Add(new Point(i==1?1:.5,i==2?1:0));}int start=mesh.Positions.Count-3;mesh.TriangleIndices.Add(start);mesh.TriangleIndices.Add(start+1);mesh.TriangleIndices.Add(start+2);
        }
        private void AddTree3D(Model3DGroup world,double x,double y,double height,int biome,int seed)
        {
            double z=y*groundDepthScale,g=TerrainHeight(x,y),trunk=height*.075;Color bark=biome==1?Color.FromRgb(48,37,29):Color.FromRgb(91,67,43);AddCone(world,new Point3D(x,g,z),new Point3D(x+Math.Sin(seed)*trunk*.4,g+height*.58,z),trunk,bark);
            if(biome==1){for(int j=0;j<3;j++){double side=j%2==0?-1:1;AddCone(world,new Point3D(x,g+height*(.38+j*.10),z),new Point3D(x+side*height*.28,g+height*(.62+j*.10),z+side*height*.04*groundDepthScale),trunk*.55,Color.FromRgb(49,38,29));}if(seed%4==0)AddMagicEllipsoid(world,new Point3D(x+height*.18,g+height*.58,z+height*.08*groundDepthScale),new Vector3D(2.2,2.2,2.2),Color.FromRgb(255,103,44));return;}
            Color[] crowns=biome==2?new[]{Color.FromRgb(37,75,79),Color.FromRgb(58,98,97),Color.FromRgb(93,129,122)}:new[]{Color.FromRgb(30,70,44),Color.FromRgb(39,91,53),Color.FromRgb(58,115,64)};for(int side=-1;side<=1;side+=2)AddCone(world,new Point3D(x,g+height*.43,z),new Point3D(x+side*height*.24,g+height*.67,z+side*height*.035*groundDepthScale),trunk*.48,bark);for(int tier=0;tier<3;tier++){double baseY=g+height*(.33+tier*.18),radius=height*(.30-tier*.065),depthRadius=radius*groundDepthScale*.72;AddCone(world,new Point3D(x,baseY,z),new Point3D(x+(seed%3-1)*height*.025,baseY+height*.42,z),radius*(1-tier*.10),crowns[Math.Min(2,tier)]);if(biome==2){AddEllipsoid(world,new Point3D(x-radius*.15,baseY+height*.15,z+radius*.15*groundDepthScale),new Vector3D(radius*.68,height*.06,depthRadius*.52),Color.FromRgb(198,215,211));}else{AddEllipsoid(world,new Point3D(x-radius*.15,baseY+height*.17,z+radius*.10*groundDepthScale),new Vector3D(radius*.56,height*.05,depthRadius*.42),Color.FromRgb(82,127,63));for(int lobe=0;lobe<3;lobe++){double a=lobe*Math.PI*2/3+(seed%5)*.21,ox=Math.Cos(a)*radius*.40,oz=Math.Sin(a)*depthRadius*.44;Color leaf=crowns[(tier+lobe+1)%crowns.Length];AddEllipsoid(world,new Point3D(x+ox,baseY+height*.15,z+oz),new Vector3D(radius*.31,height*.12,depthRadius*.31),leaf);}}}
        }
        private void AddShrub3D(Model3DGroup world,double x,double y,double size,int biome,int seed)
        {
            double z=y*groundDepthScale,h=TerrainHeight(x,y);if(biome==1&&seed%3==0){AddEllipsoid(world,new Point3D(x,h+size*.18,z),new Vector3D(size*.8,size*.22,size*.55*groundDepthScale),Color.FromRgb(70,51,38));AddEllipsoid(world,new Point3D(x-size*.35,h+size*.22,z+size*.2*groundDepthScale),new Vector3D(size*.31,size*.25,size*.29*groundDepthScale),Color.FromRgb(104,71,48));return;}Color dark=biome==2?Color.FromRgb(53,83,85):biome==1?Color.FromRgb(62,57,43):Color.FromRgb(31,79,43),light=biome==2?Color.FromRgb(106,139,137):biome==1?Color.FromRgb(109,79,51):Color.FromRgb(60,113,51);for(int i=0;i<3;i++){double ox=(i-1)*size*.42;AddEllipsoid(world,new Point3D(x+ox,h+size*.43+(i%2)*size*.12,z+(i%2-.5)*size*.28*groundDepthScale),new Vector3D(size*.48,size*.47,size*.43*groundDepthScale),i==1?light:dark);}
        }
        private void AddRock3D(Model3DGroup world,double x,double y,double radius,int biome,int seed)
        {
            double z=y*groundDepthScale,ground=TerrainHeight(x,y),height=radius*(.57+(seed%5)*.07),depth=radius*groundDepthScale;MeshGeometry3D mesh=new MeshGeometry3D();const int sides=18;double[] levels={0,.17,.43,.73,1.0};double[] rings={.54,.88,1.06,.82,.42};double phase=(seed%17)*.19;
            for(int ring=0;ring<levels.Length;ring++)for(int i=0;i<sides;i++){double a=2*Math.PI*i/sides+phase,variation=.86+.10*Math.Sin(i*2.13+seed*.37+ring*.8)+.05*Math.Cos(i*3.71-seed*.21),rr=radius*rings[ring]*variation,leanX=Math.Sin(seed*1.71)*radius*.07*levels[ring],leanZ=Math.Cos(seed*1.33)*depth*.06*levels[ring];mesh.Positions.Add(new Point3D(x+Math.Cos(a)*rr+leanX,ground+height*levels[ring],z+Math.Sin(a)*rr*groundDepthScale+leanZ));Vector3D normal=new Vector3D(Math.Cos(a)*.82,.38+levels[ring]*.44,Math.Sin(a)*.82/groundDepthScale);normal.Normalize();mesh.Normals.Add(normal);mesh.TextureCoordinates.Add(new Point((double)i/sides,levels[ring]));}
            for(int ring=0;ring<levels.Length-1;ring++)for(int i=0;i<sides;i++){int a=ring*sides+i,b=ring*sides+(i+1)%sides,c=(ring+1)*sides+i,d=(ring+1)*sides+(i+1)%sides;mesh.TriangleIndices.Add(a);mesh.TriangleIndices.Add(b);mesh.TriangleIndices.Add(c);mesh.TriangleIndices.Add(b);mesh.TriangleIndices.Add(d);mesh.TriangleIndices.Add(c);}
            int top=mesh.Positions.Count;mesh.Positions.Add(new Point3D(x+Math.Sin(seed)*radius*.035,ground+height,z+Math.Cos(seed*.7)*depth*.035));mesh.Normals.Add(new Vector3D(0,1,0));mesh.TextureCoordinates.Add(new Point(.5,1));int topRing=(levels.Length-1)*sides;for(int i=0;i<sides;i++){mesh.TriangleIndices.Add(topRing+i);mesh.TriangleIndices.Add(topRing+(i+1)%sides);mesh.TriangleIndices.Add(top);}
            mesh.Freeze();Material material=RockTextureMaterial(biome);GeometryModel3D rock=new GeometryModel3D(mesh,material){BackMaterial=material};rock.Freeze();world.Children.Add(rock);
        }
        private Material RockTextureMaterial(int biome)
        {
            Material cached=rockTextureCache[biome];if(cached!=null)return cached;int size=512;Color dark=biome==2?Color.FromRgb(60,79,84):biome==1?Color.FromRgb(54,40,31):Color.FromRgb(49,59,48),mid=biome==2?Color.FromRgb(128,147,145):biome==1?Color.FromRgb(111,80,57):Color.FromRgb(91,101,79),light=biome==2?Color.FromRgb(189,202,197):biome==1?Color.FromRgb(157,119,88):Color.FromRgb(132,142,111);DrawingGroup drawing=new DrawingGroup();using(DrawingContext dc=drawing.Open()){LinearGradientBrush baseBrush=new LinearGradientBrush(dark,mid,36);baseBrush.Freeze();dc.DrawRectangle(baseBrush,null,new Rect(0,0,size,size));Random r=new Random(4319+biome*73);for(int i=0;i<170;i++){double x=r.NextDouble()*size,y=r.NextDouble()*size,w=24+r.NextDouble()*105,h=10+r.NextDouble()*62;Color c=i%3==0?light:i%3==1?mid:dark;byte alpha=(byte)(18+r.Next(42));dc.DrawGeometry(Frozen(Color.FromArgb(alpha,c.R,c.G,c.B)),null,BlobGeometry(x,y,w,h,i+biome*19,5+r.Next(4)));}for(int i=0;i<1850;i++){double x=r.NextDouble()*size,y=r.NextDouble()*size,rad=.4+r.NextDouble()*2.4;byte a=(byte)(24+r.Next(75));Color c=i%4==0?light:dark;dc.DrawEllipse(Frozen(Color.FromArgb(a,c.R,c.G,c.B)),null,new Point(x,y),rad,rad*(.4+r.NextDouble()*.7));}for(int i=0;i<36;i++){double x=r.NextDouble()*size,y=r.NextDouble()*size,len=18+r.NextDouble()*96,dx=(r.NextDouble()-.5)*len,dy=(r.NextDouble()-.5)*len;dc.DrawLine(Stroke(Color.FromArgb(70,17,20,18),1.4),new Point(x,y),new Point(x+dx,y+dy));dc.DrawLine(Stroke(Color.FromArgb(65,light.R,light.G,light.B),.7),new Point(x-1,y-1),new Point(x+dx*.65-1,y+dy*.65-1));}if(biome==0)for(int i=0;i<115;i++){double x=r.NextDouble()*size,y=r.NextDouble()*size;dc.DrawEllipse(Frozen(Color.FromArgb(58,71,110,63)),null,new Point(x,y),4+r.NextDouble()*14,2+r.NextDouble()*7);}if(biome==2)for(int i=0;i<74;i++){double x=r.NextDouble()*size,y=r.NextDouble()*size;dc.DrawLine(Stroke(Color.FromArgb(105,221,232,225),.9+r.NextDouble()),new Point(x,y),new Point(x+2+r.NextDouble()*15,y-5-r.NextDouble()*20));}}
            DrawingVisual visual=new DrawingVisual();using(DrawingContext dc=visual.RenderOpen())dc.DrawDrawing(drawing);RenderTargetBitmap bitmap=new RenderTargetBitmap(size,size,96,96,PixelFormats.Pbgra32);bitmap.Render(visual);bitmap.Freeze();ImageBrush brush=new ImageBrush(bitmap){Stretch=Stretch.Fill,TileMode=TileMode.None};brush.Freeze();MaterialGroup group=new MaterialGroup();group.Children.Add(new DiffuseMaterial(brush));group.Children.Add(new SpecularMaterial(Frozen(Color.FromArgb(75,235,229,211)),20));group.Freeze();rockTextureCache[biome]=group;return group;
        }        private void AddCaveGates3D(Model3DGroup world,int scene)
        {
            if(path==null||path.Length<2)return;AddCaveGate3D(world,path[0],scene,true);AddCaveGate3D(world,path[path.Length-1],scene,false);
        }
        private void AddCaveGate3D(Model3DGroup world,Point point,int scene,bool entrance)
        {
            double x=point.X,y=point.Y,g=TerrainHeight(x,y),z=y*groundDepthScale,scale=MapScale;Point toward=entrance?path[1]:path[path.Length-2];double tx=toward.X-x,ty=toward.Y-y,length=Math.Sqrt(tx*tx+ty*ty);if(length<.001){tx=1;ty=0;length=1;}tx/=length;ty/=length;Vector3D across=new Vector3D(-ty,0,tx*groundDepthScale),tunnel=new Vector3D(tx,0,ty*groundDepthScale);across.Normalize();tunnel.Normalize();if(entrance)tunnel=-tunnel;Point3D origin=new Point3D(x,g,z);double outer=63*scale,inner=46*scale,spring=48*scale,wallDepth=19*scale,tunnelDepth=92*scale;const int segments=18;MeshGeometry3D frame=new MeshGeometry3D(),inside=new MeshGeometry3D(),darkness=new MeshGeometry3D();
            for(int i=0;i<segments;i++){double a0=Math.PI*i/segments,a1=Math.PI*(i+1)/segments;Point3D o0=CavePoint(origin,across,tunnel,outer*Math.Cos(a0),spring+outer*Math.Sin(a0),0),o1=CavePoint(origin,across,tunnel,outer*Math.Cos(a1),spring+outer*Math.Sin(a1),0),i0=CavePoint(origin,across,tunnel,inner*Math.Cos(a0),spring+inner*Math.Sin(a0),0),i1=CavePoint(origin,across,tunnel,inner*Math.Cos(a1),spring+inner*Math.Sin(a1),0),ob0=CavePoint(origin,across,tunnel,outer*Math.Cos(a0),spring+outer*Math.Sin(a0),wallDepth),ob1=CavePoint(origin,across,tunnel,outer*Math.Cos(a1),spring+outer*Math.Sin(a1),wallDepth);CaveQuad(frame,o0,o1,i1,i0);CaveQuad(frame,CavePoint(origin,across,tunnel,outer*Math.Cos(a0),spring+outer*Math.Sin(a0),wallDepth),CavePoint(origin,across,tunnel,outer*Math.Cos(a1),spring+outer*Math.Sin(a1),wallDepth),CavePoint(origin,across,tunnel,inner*Math.Cos(a1),spring+inner*Math.Sin(a1),wallDepth),CavePoint(origin,across,tunnel,inner*Math.Cos(a0),spring+inner*Math.Sin(a0),wallDepth));CaveQuad(frame,o0,ob0,ob1,o1);Point3D it0=CavePoint(origin,across,tunnel,inner*Math.Cos(a0),spring+inner*Math.Sin(a0),tunnelDepth),it1=CavePoint(origin,across,tunnel,inner*Math.Cos(a1),spring+inner*Math.Sin(a1),tunnelDepth);CaveQuad(inside,i0,it0,it1,i1);}
            for(int side=-1;side<=1;side+=2){double outS=side*outer,inS=side*inner;Point3D of=CavePoint(origin,across,tunnel,outS,0,0),ot=CavePoint(origin,across,tunnel,outS,spring,0),it=CavePoint(origin,across,tunnel,inS,spring,0),inf=CavePoint(origin,across,tunnel,inS,0,0),ob=CavePoint(origin,across,tunnel,outS,0,wallDepth),otb=CavePoint(origin,across,tunnel,outS,spring,wallDepth),itb=CavePoint(origin,across,tunnel,inS,spring,wallDepth),infb=CavePoint(origin,across,tunnel,inS,0,tunnelDepth);CaveQuad(frame,of,ot,it,inf);CaveQuad(frame,ob,otb,itb,CavePoint(origin,across,tunnel,inS,0,wallDepth));CaveQuad(frame,of,ob,otb,ot);CaveQuad(inside,inf,it,itb,infb);}
            Point3D left=CavePoint(origin,across,tunnel,-inner,0,tunnelDepth),right=CavePoint(origin,across,tunnel,inner,0,tunnelDepth),leftTop=CavePoint(origin,across,tunnel,-inner,spring,tunnelDepth),rightTop=CavePoint(origin,across,tunnel,inner,spring,tunnelDepth);CaveQuad(darkness,left,right,rightTop,leftTop);for(int i=0;i<segments;i++){double a0=Math.PI*i/segments,a1=Math.PI*(i+1)/segments;Point3D center=CavePoint(origin,across,tunnel,0,spring,tunnelDepth),p0=CavePoint(origin,across,tunnel,inner*Math.Cos(a0),spring+inner*Math.Sin(a0),tunnelDepth),p1=CavePoint(origin,across,tunnel,inner*Math.Cos(a1),spring+inner*Math.Sin(a1),tunnelDepth);CaveTriangle(darkness,center,p0,p1);}
            AddCaveMesh(world,frame,RockTextureMaterial(scene%3));AddCaveMesh(world,inside,Material3D(scene%3==1?Color.FromRgb(38,31,26):scene%3==2?Color.FromRgb(43,54,56):Color.FromRgb(34,39,31)));AddCaveMesh(world,darkness,Material3D(Color.FromRgb(13,14,13)));Color glow=entrance?scene%3==1?Color.FromRgb(255,124,45):scene%3==2?Color.FromRgb(137,220,248):Color.FromRgb(226,178,87):scene%3==2?Color.FromRgb(117,191,231):Color.FromRgb(202,120,54);Point3D light=origin+tunnel*(14*scale)+new Vector3D(0,4*scale,0);AddMagicEllipsoid(world,light,new Vector3D(8*scale,2.1*scale,2.1*scale),Color.FromArgb(105,glow.R,glow.G,glow.B));
        }
        private static Point3D CavePoint(Point3D origin,Vector3D across,Vector3D tunnel,double lateral,double height,double depth){return origin+across*lateral+tunnel*depth+new Vector3D(0,height,0);}
        private static void CaveTriangle(MeshGeometry3D mesh,Point3D a,Point3D b,Point3D c){Vector3D normal=Vector3D.CrossProduct(b-a,c-a);if(normal.LengthSquared<.000001)normal=new Vector3D(0,1,0);normal.Normalize();int n=mesh.Positions.Count;mesh.Positions.Add(a);mesh.Positions.Add(b);mesh.Positions.Add(c);mesh.Normals.Add(normal);mesh.Normals.Add(normal);mesh.Normals.Add(normal);mesh.TextureCoordinates.Add(new Point(0,0));mesh.TextureCoordinates.Add(new Point(1,0));mesh.TextureCoordinates.Add(new Point(1,1));mesh.TriangleIndices.Add(n);mesh.TriangleIndices.Add(n+1);mesh.TriangleIndices.Add(n+2);}
        private static void CaveQuad(MeshGeometry3D mesh,Point3D a,Point3D b,Point3D c,Point3D d){CaveTriangle(mesh,a,b,c);CaveTriangle(mesh,a,c,d);}
        private static void AddCaveMesh(Model3DGroup world,MeshGeometry3D mesh,Material material){if(mesh.Positions.Count==0)return;mesh.Freeze();GeometryModel3D model=new GeometryModel3D(mesh,material){BackMaterial=material};model.Freeze();world.Children.Add(model);}
        private void UpdateEnemyModels()
        {
            foreach(Enemy e in enemies){EnemyRig3D rig=e.Model;if(rig==null)continue;double cycle=clock*8.7+e.Phase,stride=Math.Sin(cycle),knee=Math.Max(0,-stride);if(rig.Quadruped){if(rig.WargFrontLeft!=null)rig.WargFrontLeft.Angle=stride*31;if(rig.WargFrontRight!=null)rig.WargFrontRight.Angle=-stride*31;if(rig.WargBackLeft!=null)rig.WargBackLeft.Angle=-stride*31;if(rig.WargBackRight!=null)rig.WargBackRight.Angle=stride*31;}else{if(rig.LeftHip!=null)rig.LeftHip.Angle=stride*30;if(rig.RightHip!=null)rig.RightHip.Angle=-stride*30;if(rig.LeftKnee!=null)rig.LeftKnee.Angle=knee*42;if(rig.RightKnee!=null)rig.RightKnee.Angle=Math.Max(0,stride)*42;if(rig.LeftShoulder!=null)rig.LeftShoulder.Angle=-stride*23;if(rig.RightShoulder!=null)rig.RightShoulder.Angle=stride*23;if(rig.LeftElbow!=null)rig.LeftElbow.Angle=12+Math.Max(0,stride)*19;if(rig.RightElbow!=null)rig.RightElbow.Angle=12+Math.Max(0,-stride)*19;if(rig.Torso!=null)rig.Torso.Angle=Math.Sin(cycle*2)*3;if(rig.Head!=null)rig.Head.Angle=Math.Sin(cycle*2+.6)*2.5;}
                double dx=1,dy=0;if(e.PathSegment>=0&&e.PathSegment<motionPath.Length-1){Point a=motionPath[e.PathSegment],b=motionPath[e.PathSegment+1];dx=b.X-a.X;dy=b.Y-a.Y;}rig.Yaw.Angle=-Math.Atan2(dy,dx)*180/Math.PI;double height=e.Kind=="goblin"?90:e.Kind=="orc"?118:e.Kind=="uruk"?132:e.Kind=="warg"?82:e.Kind=="troll"?220:e.Kind=="nazgul"?158:110;if(e.Boss)height*=1.18;height*=1.10;double scale=height*MapScale/(rig.HeightNorm*.848);rig.ScaleTransform.ScaleX=scale;rig.ScaleTransform.ScaleY=scale;rig.ScaleTransform.ScaleZ=scale;rig.PositionTransform.OffsetX=e.X;rig.PositionTransform.OffsetY=TerrainHeight(e.X,e.Y)+2.8*MapScale+Math.Abs(stride)*1.5*MapScale;rig.PositionTransform.OffsetZ=e.Y*groundDepthScale;
            }
        }

        private EnemyRig3D CreateEnemyModel(string kind)
        {
            EnemyRig3D rig=new EnemyRig3D();Model3DGroup model=new Model3DGroup();rig.ScaleTransform=new ScaleTransform3D(1,1,1);rig.Yaw=new AxisAngleRotation3D(new Vector3D(0,1,0),0);rig.PositionTransform=new TranslateTransform3D();Transform3DGroup transform=new Transform3DGroup();transform.Children.Add(rig.ScaleTransform);transform.Children.Add(new RotateTransform3D(rig.Yaw));transform.Children.Add(rig.PositionTransform);rig.Visual=new ModelVisual3D{Content=model,Transform=transform};
            if(kind=="warg")BuildWargModel(model,rig);else BuildHumanoidModel(model,rig,kind);return rig;
        }
        private Material Material3D(Color color){Material material;if(!material3DCache.TryGetValue(color,out material)){DiffuseMaterial diffuse=new DiffuseMaterial(Frozen(color));SpecularMaterial shine=new SpecularMaterial(Frozen(Color.FromRgb(196,197,183)),color.A<255?18:30);MaterialGroup group=new MaterialGroup();group.Children.Add(diffuse);group.Children.Add(shine);group.Freeze();material=group;material3DCache[color]=material;}return material;}
        private MeshGeometry3D SphereMesh(){if(unitSphereMesh!=null)return unitSphereMesh;MeshGeometry3D mesh=new MeshGeometry3D();const int slices=20,rings=14;for(int y=0;y<=rings;y++){double v=(double)y/rings,phi=Math.PI*v;for(int x=0;x<=slices;x++){double u=(double)x/slices,theta=2*Math.PI*u;Vector3D n=new Vector3D(Math.Sin(phi)*Math.Cos(theta),Math.Cos(phi),Math.Sin(phi)*Math.Sin(theta));mesh.Positions.Add(new Point3D(n.X,n.Y,n.Z));mesh.Normals.Add(n);mesh.TextureCoordinates.Add(new Point(u,v));}}for(int y=0;y<rings;y++)for(int x=0;x<slices;x++){int a=y*(slices+1)+x,b=a+slices+1;mesh.TriangleIndices.Add(a);mesh.TriangleIndices.Add(b);mesh.TriangleIndices.Add(a+1);mesh.TriangleIndices.Add(a+1);mesh.TriangleIndices.Add(b);mesh.TriangleIndices.Add(b+1);}mesh.Freeze();unitSphereMesh=mesh;return mesh;}
        private Material Emissive3D(Color color){Material material;if(!emissive3DCache.TryGetValue(color,out material)){MaterialGroup group=new MaterialGroup();group.Children.Add(Material3D(color));group.Children.Add(new EmissiveMaterial(Frozen(color)));group.Freeze();material=group;emissive3DCache[color]=material;}return material;}
        private ScaleTransform3D AddEllipsoid(Model3DGroup group,Point3D center,Vector3D radius,Color color){return AddEllipsoidMaterial(group,center,radius,Material3D(color));}
        private ScaleTransform3D AddMagicEllipsoid(Model3DGroup group,Point3D center,Vector3D radius,Color color){return AddEllipsoidMaterial(group,center,radius,Emissive3D(color));}
        private ScaleTransform3D AddEllipsoidMaterial(Model3DGroup group,Point3D center,Vector3D radius,Material material){ScaleTransform3D scale=new ScaleTransform3D(radius.X,radius.Y,radius.Z);Transform3DGroup transform=new Transform3DGroup();transform.Children.Add(scale);transform.Children.Add(new TranslateTransform3D(center.X,center.Y,center.Z));transform.Freeze();GeometryModel3D shape=new GeometryModel3D(SphereMesh(),material){BackMaterial=material,Transform=transform};shape.Freeze();group.Children.Add(shape);return scale;}
        private void AddCone(Model3DGroup group,Point3D start,Point3D end,double radius,Color color)
        {
            Vector3D axis=end-start;if(axis.Length<.001)return;axis.Normalize();Vector3D reference=Math.Abs(axis.Y)<.88?new Vector3D(0,1,0):new Vector3D(1,0,0);Vector3D u=Vector3D.CrossProduct(axis,reference);u.Normalize();Vector3D v=Vector3D.CrossProduct(axis,u);v.Normalize();MeshGeometry3D mesh=new MeshGeometry3D();const int sides=12;
            for(int i=0;i<sides;i++){double a=2*Math.PI*i/sides,b=2*Math.PI*(i+1)/sides;Vector3D ra=u*Math.Cos(a)+v*Math.Sin(a),rb=u*Math.Cos(b)+v*Math.Sin(b);Point3D p0=start+ra*radius,p1=start+rb*radius;int n=mesh.Positions.Count;mesh.Positions.Add(p0);mesh.Positions.Add(p1);mesh.Positions.Add(end);Vector3D normal=Vector3D.CrossProduct(p1-p0,end-p0);normal.Normalize();mesh.Normals.Add(normal);mesh.Normals.Add(normal);mesh.Normals.Add(normal);mesh.TriangleIndices.Add(n);mesh.TriangleIndices.Add(n+1);mesh.TriangleIndices.Add(n+2);}
            mesh.Freeze();Material material=Material3D(color);GeometryModel3D cone=new GeometryModel3D(mesh,material){BackMaterial=material};cone.Freeze();group.Children.Add(cone);
        }
        private void BuildWargModel(Model3DGroup model,EnemyRig3D rig)
        {
            rig.HeightNorm=1.68;rig.Quadruped=true;Color fur=Color.FromRgb(55,48,40),muzzle=Color.FromRgb(114,91,65),saddle=Color.FromRgb(89,56,39),iron=Color.FromRgb(86,78,67),eye=Color.FromRgb(237,157,55),bone=Color.FromRgb(218,194,143);
            AddEllipsoid(model,new Point3D(-.02,.83,0),new Vector3D(.70,.42,.36),fur);AddEllipsoid(model,new Point3D(.40,.95,0),new Vector3D(.43,.36,.31),fur);AddEllipsoid(model,new Point3D(.70,.82,0),new Vector3D(.29,.22,.245),muzzle);AddEllipsoid(model,new Point3D(.83,.90,0),new Vector3D(.22,.13,.21),Color.FromRgb(49,38,33));
            for(int side=-1;side<=1;side+=2){double z=side*.235;AddEllipsoid(model,new Point3D(.55,1.19,z),new Vector3D(.14,.19,.12),fur);AddCone(model,new Point3D(.56,1.28,z),new Point3D(.47,1.54,z+side*.045),.09,bone);AddEllipsoid(model,new Point3D(.60,1.04,z*1.10),new Vector3D(.055,.05,.035),eye);AddEllipsoid(model,new Point3D(.62,1.04,z*1.15),new Vector3D(.018,.028,.014),Color.FromRgb(20,17,14));}
            AddEllipsoid(model,new Point3D(-.13,1.20,0),new Vector3D(.55,.19,.38),saddle);AddEllipsoid(model,new Point3D(-.10,1.30,0),new Vector3D(.42,.11,.31),iron);AddEllipsoid(model,new Point3D(-.18,1.38,0),new Vector3D(.20,.15,.22),Color.FromRgb(109,42,34));AddEllipsoid(model,new Point3D(-.73,.88,0),new Vector3D(.25,.12,.14),fur);AddCone(model,new Point3D(-.85,.89,0),new Point3D(-1.18,1.02,0),.10,fur);
            rig.WargFrontLeft=NewRigRotation();rig.WargFrontRight=NewRigRotation();rig.WargBackLeft=NewRigRotation();rig.WargBackRight=NewRigRotation();AddWargLeg(model,rig.WargFrontLeft,.39,-1,fur,iron);AddWargLeg(model,rig.WargFrontRight,.39,1,fur,iron);AddWargLeg(model,rig.WargBackLeft,-.42,-1,fur,iron);AddWargLeg(model,rig.WargBackRight,-.42,1,fur,iron);
            Model3DGroup rider=new Model3DGroup();AddEllipsoid(rider,new Point3D(-.12,1.61,0),new Vector3D(.19,.30,.18),Color.FromRgb(69,42,32));AddEllipsoid(rider,new Point3D(-.04,1.93,0),new Vector3D(.17,.18,.16),Color.FromRgb(122,104,73));AddEllipsoid(rider,new Point3D(.05,1.95,0),new Vector3D(.13,.12,.17),Color.FromRgb(68,55,43));AddEllipsoid(rider,new Point3D(-.10,1.69,.16),new Vector3D(.23,.12,.07),iron);AddEllipsoid(rider,new Point3D(-.10,1.69,-.16),new Vector3D(.23,.12,.07),iron);model.Children.Add(rider);rig.HeightNorm=2.15;
        }
        private void AddWargLeg(Model3DGroup root,AxisAngleRotation3D rotation,double x,int side,Color fur,Color armor)
        {
            double z=side*.22;Model3DGroup leg=new Model3DGroup();leg.Transform=new RotateTransform3D(rotation,new Point3D(x,.77,z));AddEllipsoid(leg,new Point3D(x,.48,z),new Vector3D(.15,.39,.13),fur);AddEllipsoid(leg,new Point3D(x+.06,.12,z),new Vector3D(.20,.13,.16),armor);AddEllipsoid(leg,new Point3D(x+.18,.09,z),new Vector3D(.16,.08,.14),Color.FromRgb(51,43,37));root.Children.Add(leg);
        }
        private void BuildHumanoidModel(Model3DGroup model,EnemyRig3D rig,string kind)
        {
            rig.HeightNorm=2.42;bool goblin=kind=="goblin",uruk=kind=="uruk",troll=kind=="troll",nazgul=kind=="nazgul";
            Color skin=goblin?Color.FromRgb(107,150,59):troll?Color.FromRgb(102,123,124):nazgul?Color.FromRgb(73,83,99):uruk?Color.FromRgb(103,91,75):Color.FromRgb(115,113,83);
            Color cloth=goblin?Color.FromRgb(81,65,37):troll?Color.FromRgb(93,76,55):nazgul?Color.FromRgb(28,38,54):uruk?Color.FromRgb(53,48,48):Color.FromRgb(67,45,35);
            Color armor=goblin?Color.FromRgb(87,88,63):troll?Color.FromRgb(96,103,101):nazgul?Color.FromRgb(50,67,86):uruk?Color.FromRgb(63,68,66):Color.FromRgb(84,78,64);
            Color trim=uruk?Color.FromRgb(141,50,39):nazgul?Color.FromRgb(104,160,190):Color.FromRgb(160,119,62),eye=nazgul?Color.FromRgb(112,219,255):goblin?Color.FromRgb(231,216,87):Color.FromRgb(245,107,57),bone=Color.FromRgb(212,193,148);
            Model3DGroup torso=new Model3DGroup();rig.Torso=new AxisAngleRotation3D(new Vector3D(0,0,1),0);torso.Transform=new RotateTransform3D(rig.Torso,new Point3D(0,1.48,0));
            AddEllipsoid(torso,new Point3D(0,1.48,0),new Vector3D(.32,.43,.29),cloth);AddEllipsoid(torso,new Point3D(.11,1.52,0),new Vector3D(.22,.32,.285),armor);AddEllipsoid(torso,new Point3D(.225,1.53,0),new Vector3D(.035,.24,.19),trim);AddEllipsoid(torso,new Point3D(.253,1.53,0),new Vector3D(.018,.20,.15),armor);AddEllipsoid(torso,new Point3D(.02,1.14,0),new Vector3D(.33,.12,.31),nazgul?cloth:trim);AddEllipsoid(torso,new Point3D(.015,1.04,0),new Vector3D(.30,.19,.30),cloth);AddEllipsoid(torso,new Point3D(.02,.97,.16),new Vector3D(.22,.23,.05),trim);AddEllipsoid(torso,new Point3D(.02,.95,-.16),new Vector3D(.22,.23,.05),cloth);AddEllipsoid(torso,new Point3D(0,1.80,0),new Vector3D(.27,.15,.32),armor);AddEllipsoid(torso,new Point3D(0,1.83,.29),new Vector3D(.22,.13,.14),trim);AddEllipsoid(torso,new Point3D(0,1.83,-.29),new Vector3D(.22,.13,.14),trim);
            if(troll){AddEllipsoid(torso,new Point3D(-.06,1.86,.18),new Vector3D(.18,.23,.18),armor);AddEllipsoid(torso,new Point3D(-.06,1.86,-.18),new Vector3D(.18,.23,.18),armor);}
            if(uruk){AddEllipsoid(torso,new Point3D(.17,1.62,.11),new Vector3D(.025,.16,.035),Color.FromRgb(153,53,43));AddEllipsoid(torso,new Point3D(.17,1.43,-.10),new Vector3D(.025,.14,.035),Color.FromRgb(153,53,43));}
            if(nazgul){AddEllipsoid(torso,new Point3D(-.13,1.45,0),new Vector3D(.32,.42,.35),Color.FromArgb(225,15,22,36));AddEllipsoid(torso,new Point3D(-.18,1.12,.10),new Vector3D(.26,.27,.23),Color.FromArgb(205,18,25,39));AddEllipsoid(torso,new Point3D(-.18,1.12,-.10),new Vector3D(.26,.27,.23),Color.FromArgb(205,18,25,39));}
            model.Children.Add(torso);

            Point3D headPivot=new Point3D(.025,1.94,0);Model3DGroup head=new Model3DGroup();rig.Head=new AxisAngleRotation3D(new Vector3D(0,0,1),0);head.Transform=new RotateTransform3D(rig.Head,headPivot);AddEllipsoid(head,new Point3D(.035,1.99,0),new Vector3D(.255,.28,.235),skin);AddEllipsoid(head,new Point3D(.19,1.93,0),new Vector3D(.14,.12,.16),skin);AddEllipsoid(head,new Point3D(.257,1.96,0),new Vector3D(.075,.055,.075),Color.FromRgb(58,45,37));
            for(int side=-1;side<=1;side+=2){double z=side*.125;AddEllipsoid(head,new Point3D(.18,2.09,z),new Vector3D(.075,.055,.060),Color.FromRgb(38,28,23));AddEllipsoid(head,new Point3D(.232,2.09,z),new Vector3D(.035,.032,.032),eye);AddEllipsoid(head,new Point3D(.258,2.09,z),new Vector3D(.014,.024,.014),Color.FromRgb(15,17,19));AddCone(head,new Point3D(-.005,1.88,z),new Point3D(.115,2.04,z),.073,bone);}
            AddEllipsoid(head,new Point3D(.02,2.23,0),new Vector3D(.25,.10,.245),goblin?cloth:armor);AddEllipsoid(head,new Point3D(.12,2.20,0),new Vector3D(.18,.07,.255),trim);
            if(goblin)for(int side=-1;side<=1;side+=2)AddCone(head,new Point3D(-.04,2.00,side*.18),new Point3D(-.15,2.24,side*.34),.085,skin);
            if(nazgul){AddEllipsoid(head,new Point3D(.10,2.00,0),new Vector3D(.205,.255,.20),Color.FromRgb(25,34,49));AddEllipsoid(head,new Point3D(.295,2.065,.08),new Vector3D(.028,.025,.045),eye);AddEllipsoid(head,new Point3D(.295,2.065,-.08),new Vector3D(.028,.025,.045),eye);}
            model.Children.Add(head);

            rig.LeftHip=NewRigRotation();rig.RightHip=NewRigRotation();rig.LeftKnee=NewRigRotation();rig.RightKnee=NewRigRotation();AddHumanoidLeg(model,rig.LeftHip,rig.LeftKnee,-1,cloth,armor,trim);AddHumanoidLeg(model,rig.RightHip,rig.RightKnee,1,cloth,armor,trim);
            rig.LeftShoulder=NewRigRotation();rig.RightShoulder=NewRigRotation();rig.LeftElbow=NewRigRotation();rig.RightElbow=NewRigRotation();AddHumanoidArm(model,rig.LeftShoulder,rig.LeftElbow,-1,skin,cloth,armor,trim,kind);AddHumanoidArm(model,rig.RightShoulder,rig.RightElbow,1,skin,cloth,armor,trim,kind);
        }
        private void AddHumanoidLeg(Model3DGroup root,AxisAngleRotation3D hipRotation,AxisAngleRotation3D kneeRotation,int side,Color cloth,Color armor,Color trim)
        {
            double z=side*.145;Model3DGroup leg=new Model3DGroup();Point3D hip=new Point3D(0,1.14,z);leg.Transform=new RotateTransform3D(hipRotation,hip);AddEllipsoid(leg,new Point3D(0,.91,z),new Vector3D(.19,.34,.15),cloth);AddEllipsoid(leg,new Point3D(.04,.66,z),new Vector3D(.18,.13,.16),armor);
            Model3DGroup lower=new Model3DGroup();Point3D knee=new Point3D(0,.65,z);lower.Transform=new RotateTransform3D(kneeRotation,knee);AddEllipsoid(lower,new Point3D(-.01,.37,z),new Vector3D(.145,.29,.125),armor);AddEllipsoid(lower,new Point3D(.02,.37,z+side*.015),new Vector3D(.151,.255,.132),cloth);AddEllipsoid(lower,new Point3D(.11,.105,z),new Vector3D(.235,.115,.16),trim);AddEllipsoid(lower,new Point3D(.24,.08,z),new Vector3D(.11,.075,.155),Color.FromRgb(46,39,33));leg.Children.Add(lower);root.Children.Add(leg);
        }
        private void AddHumanoidArm(Model3DGroup root,AxisAngleRotation3D shoulderRotation,AxisAngleRotation3D elbowRotation,int side,Color skin,Color cloth,Color armor,Color trim,string kind)
        {
            double z=side*.34;Model3DGroup upper=new Model3DGroup();Point3D shoulder=new Point3D(0,1.78,z);upper.Transform=new RotateTransform3D(shoulderRotation,shoulder);AddEllipsoid(upper,new Point3D(0,1.68,z+side*.045),new Vector3D(.205,.205,.205),armor);AddEllipsoid(upper,new Point3D(.01,1.48,z+side*.09),new Vector3D(.145,.30,.135),skin);
            Model3DGroup lower=new Model3DGroup();Point3D elbow=new Point3D(.01,1.25,z+side*.09);lower.Transform=new RotateTransform3D(elbowRotation,elbow);AddEllipsoid(lower,new Point3D(.065,1.23,z+side*.10),new Vector3D(.14,.27,.12),cloth);AddEllipsoid(lower,new Point3D(.10,1.01,z+side*.10),new Vector3D(.145,.105,.13),trim);AddEllipsoid(lower,new Point3D(.20,.90,z+side*.10),new Vector3D(.15,.13,.12),skin);
            if(side>0){if(kind=="troll"){AddEllipsoid(lower,new Point3D(.38,.91,z+side*.10),new Vector3D(.32,.085,.085),Color.FromRgb(74,52,38));AddEllipsoid(lower,new Point3D(.67,.91,z+side*.10),new Vector3D(.24,.23,.20),Color.FromRgb(108,96,76));AddCone(lower,new Point3D(.67,.98,z+side*.10),new Point3D(.75,1.22,z+side*.10),.09,Color.FromRgb(199,181,135));AddCone(lower,new Point3D(.67,.84,z+side*.10),new Point3D(.75,.61,z+side*.10),.09,Color.FromRgb(199,181,135));}else{AddEllipsoid(lower,new Point3D(.34,.92,z+side*.10),new Vector3D(.30,.075,.065),kind=="nazgul"?Color.FromRgb(84,126,155):Color.FromRgb(75,69,62));AddCone(lower,new Point3D(.58,.92,z+side*.10),new Point3D(.76,.94,z+side*.10),.07,trim);}}
            upper.Children.Add(lower);root.Children.Add(upper);
        }
        private static AxisAngleRotation3D NewRigRotation(){return new AxisAngleRotation3D(new Vector3D(0,0,1),0);}

        private void SetBuildGhost(HeroType type)
        {
            string id=type==null?null:type.Id;
            if(buildGhostVisual!=null&&buildGhostType==id){UpdateBuildGhost();return;}
            if(buildGhostVisual!=null&&worldView!=null)worldView.Children.Remove(buildGhostVisual);
            buildGhostVisual=null;buildGhostScale=null;buildGhostPosition=null;buildGhostType=id;
            if(type==null||worldView==null)return;
            Color primary=type.Id=="gondor"?Color.FromRgb(100,38,55):type.Id=="elf"?Color.FromRgb(70,157,112):type.Id=="dwarf"?Color.FromRgb(207,83,46):type.Id=="aura"?Color.FromRgb(196,70,120):Color.FromRgb(99,175,216);
            Color cloth=Color.FromRgb(45,49,59),skin=Color.FromRgb(222,180,146),gold=Color.FromRgb(232,199,126);
            Model3DGroup silhouette=new Model3DGroup();
            AddGhostEllipsoid(silhouette,new Point3D(-.15,1.04,0),new Vector3D(.20,.52,.30),primary);
            AddGhostEllipsoid(silhouette,new Point3D(.02,1.34,0),new Vector3D(.34,.40,.29),cloth);
            AddGhostEllipsoid(silhouette,new Point3D(.12,1.43,0),new Vector3D(.25,.30,.30),primary);
            AddGhostEllipsoid(silhouette,new Point3D(.01,.91,0),new Vector3D(.32,.20,.29),primary);
            AddGhostEllipsoid(silhouette,new Point3D(-.02,.54,.15),new Vector3D(.16,.42,.14),cloth);
            AddGhostEllipsoid(silhouette,new Point3D(-.02,.54,-.15),new Vector3D(.16,.42,.14),cloth);
            AddGhostEllipsoid(silhouette,new Point3D(.03,1.97,0),new Vector3D(.23,.26,.22),skin);
            AddGhostEllipsoid(silhouette,new Point3D(-.01,2.18,0),new Vector3D(.25,.12,.24),type.Id=="ice"?gold:primary);
            AddGhostEllipsoid(silhouette,new Point3D(0,1.72,.30),new Vector3D(.24,.19,.14),gold);
            AddGhostEllipsoid(silhouette,new Point3D(0,1.72,-.30),new Vector3D(.24,.19,.14),gold);
            AddGhostEllipsoid(silhouette,new Point3D(.30,1.03,.36),new Vector3D(.14,.31,.13),skin);
            AddGhostEllipsoid(silhouette,new Point3D(.37,.75,.38),new Vector3D(.12,.12,.12),primary);
            AddGhostEllipsoid(silhouette,new Point3D(.33,1.03,-.36),new Vector3D(.14,.31,.13),skin);
            AddGhostEllipsoid(silhouette,new Point3D(.39,.75,-.38),new Vector3D(.12,.12,.12),primary);
            if(type.Id=="gondor")AddGhostEllipsoid(silhouette,new Point3D(.76,.88,.40),new Vector3D(.48,.075,.065),Color.FromRgb(40,34,43));
            else if(type.Id=="elf"||type.Id=="dwarf")AddGhostEllipsoid(silhouette,new Point3D(.61,1.10,.40),new Vector3D(.20,.20,.20),primary);
            else if(type.Id=="ice")AddGhostEllipsoid(silhouette,new Point3D(.70,1.05,.40),new Vector3D(.39,.07,.07),Color.FromRgb(175,233,248));
            else AddGhostEllipsoid(silhouette,new Point3D(.60,1.08,.40),new Vector3D(.27,.045,.045),primary);
            buildGhostScale=new ScaleTransform3D(1,1,1);buildGhostPosition=new TranslateTransform3D();Transform3DGroup pose=new Transform3DGroup();pose.Children.Add(buildGhostScale);pose.Children.Add(buildGhostPosition);buildGhostVisual=new ModelVisual3D{Content=silhouette,Transform=pose};worldView.Children.Add(buildGhostVisual);UpdateBuildGhost();
        }
        private void AddGhostEllipsoid(Model3DGroup group,Point3D center,Vector3D radius,Color color)
        {
            Color translucent=Color.FromArgb(118,color.R,color.G,color.B);DiffuseMaterial material=new DiffuseMaterial(Frozen(translucent));material.Freeze();ScaleTransform3D scale=new ScaleTransform3D(radius.X,radius.Y,radius.Z);Transform3DGroup transform=new Transform3DGroup();transform.Children.Add(scale);transform.Children.Add(new TranslateTransform3D(center.X,center.Y,center.Z));transform.Freeze();GeometryModel3D shape=new GeometryModel3D(SphereMesh(),material){BackMaterial=material,Transform=transform};shape.Freeze();group.Children.Add(shape);
        }
        private void UpdateBuildGhost()
        {
            if(buildGhostVisual==null||buildGhostScale==null||buildGhostPosition==null)return;
            double scale=112*MapScale/(2.72*.848);buildGhostScale.ScaleX=scale;buildGhostScale.ScaleY=scale;buildGhostScale.ScaleZ=scale;
            if(selectedType==null||mouseWorld.X<0){buildGhostPosition.OffsetY=-10000;return;}
            buildGhostPosition.OffsetX=mouseWorld.X;buildGhostPosition.OffsetY=TerrainHeight(mouseWorld.X,mouseWorld.Y);buildGhostPosition.OffsetZ=mouseWorld.Y*groundDepthScale;
        }

        private ScaleTransform3D AddAnimatedEllipsoid(Model3DGroup group,Point3D center,Vector3D radius,Color color)
        {
            ScaleTransform3D scale=new ScaleTransform3D(radius.X,radius.Y,radius.Z);Transform3DGroup transform=new Transform3DGroup();transform.Children.Add(scale);transform.Children.Add(new TranslateTransform3D(center.X,center.Y,center.Z));Material material=Material3D(color);GeometryModel3D shape=new GeometryModel3D(SphereMesh(),material){BackMaterial=material,Transform=transform};group.Children.Add(shape);return scale;
        }
        private TowerModel3D CreateTowerModel(Tower tower)
        {
            TowerModel3D rig=new TowerModel3D{TypeId=tower.Type.Id,Level=tower.Level,Phase=(tower.X*.017+tower.Y*.031)%6.28};Model3DGroup model=new Model3DGroup();rig.ScaleTransform=new ScaleTransform3D(1,1,1);rig.Yaw=new AxisAngleRotation3D(new Vector3D(0,1,0),0);rig.PositionTransform=new TranslateTransform3D();Transform3DGroup transform=new Transform3DGroup();transform.Children.Add(rig.ScaleTransform);transform.Children.Add(new RotateTransform3D(rig.Yaw));transform.Children.Add(rig.PositionTransform);rig.Visual=new ModelVisual3D{Content=model,Transform=transform};BuildTowerCharacter(model,rig,tower);return rig;
        }
        private void BuildTowerCharacter(Model3DGroup model,TowerModel3D rig,Tower tower)
        {
            string id=tower.Type.Id;int level=tower.Level;Color skin=Color.FromRgb(228,186,153),hair,cloth,cloak,armor,accent,magic;
            if(id=="gondor"){hair=Color.FromRgb(29,25,31);cloth=Color.FromRgb(30,31,39);cloak=Color.FromRgb(42,31,41);armor=Color.FromRgb(70,67,76);accent=Color.FromRgb(179,55,49);magic=Color.FromRgb(29,14,35);}
            else if(id=="elf"){hair=Color.FromRgb(23,36,47);cloth=Color.FromRgb(35,67,57);cloak=Color.FromRgb(26,81,59);armor=Color.FromRgb(62,93,72);accent=Color.FromRgb(205,170,91);magic=Color.FromRgb(172,244,206);}
            else if(id=="dwarf"){hair=Color.FromRgb(190,54,39);cloth=Color.FromRgb(48,34,37);cloak=Color.FromRgb(105,42,37);armor=Color.FromRgb(82,63,56);accent=Color.FromRgb(218,126,56);magic=Color.FromRgb(255,127,38);}
            else if(id=="aura"){hair=Color.FromRgb(175,48,76);cloth=Color.FromRgb(55,34,57);cloak=Color.FromRgb(92,37,68);armor=Color.FromRgb(104,59,83);accent=Color.FromRgb(218,99,134);magic=Color.FromRgb(236,92,151);}
            else{hair=Color.FromRgb(203,212,220);cloth=Color.FromRgb(43,67,101);cloak=Color.FromRgb(43,89,128);armor=Color.FromRgb(100,142,174);accent=Color.FromRgb(180,224,237);magic=Color.FromRgb(117,218,255);}
            Color lightTrim=level>=3?Color.FromRgb(247,218,153):accent;rig.HeightNorm=2.72;
            Model3DGroup torso=new Model3DGroup();rig.Torso=NewRigRotation();torso.Transform=new RotateTransform3D(rig.Torso,new Point3D(0,1.35,0));
            AddEllipsoid(torso,new Point3D(-.18,1.11,0),new Vector3D(.20,.55,.33),cloak);AddEllipsoid(torso,new Point3D(-.31,.90,0),new Vector3D(.16,.28,.29),id=="aura"?cloak:cloth);AddEllipsoid(torso,new Point3D(0,1.37,0),new Vector3D(.34,.43,.30),cloth);AddEllipsoid(torso,new Point3D(.10,1.43,0),new Vector3D(.25,.34,.30),armor);AddEllipsoid(torso,new Point3D(.265,1.43,0),new Vector3D(.035,.26,.22),lightTrim);AddEllipsoid(torso,new Point3D(.285,1.43,0),new Vector3D(.018,.22,.17),cloth);AddEllipsoid(torso,new Point3D(.01,1.03,0),new Vector3D(.34,.14,.31),accent);AddEllipsoid(torso,new Point3D(.015,.92,0),new Vector3D(.33,.22,.30),cloak);AddEllipsoid(torso,new Point3D(.01,.87,.19),new Vector3D(.25,.24,.07),cloth);AddEllipsoid(torso,new Point3D(.01,.87,-.19),new Vector3D(.25,.24,.07),cloak);AddEllipsoid(torso,new Point3D(.04,1.73,0),new Vector3D(.34,.16,.36),armor);AddEllipsoid(torso,new Point3D(.05,1.77,.30),new Vector3D(.23,.12,.12),lightTrim);AddEllipsoid(torso,new Point3D(.05,1.77,-.30),new Vector3D(.23,.12,.12),lightTrim);AddEllipsoid(torso,new Point3D(.245,1.41,.03),new Vector3D(.045,.12,.07),magic);
            AddCloakMesh(torso,cloak,lightTrim,level,rig);AddHeroTorsoDetails(torso,id,level,cloth,cloak,armor,accent,magic,lightTrim);
            if(level>=1){AddEllipsoid(torso,new Point3D(.04,1.78,.36),new Vector3D(.25,.17,.12),lightTrim);AddEllipsoid(torso,new Point3D(.04,1.78,-.36),new Vector3D(.25,.17,.12),lightTrim);}
            if(level>=2){AddEllipsoid(torso,new Point3D(-.22,1.05,.22),new Vector3D(.18,.42,.11),id=="ice"?Color.FromRgb(45,105,153):cloak);AddEllipsoid(torso,new Point3D(-.22,1.05,-.22),new Vector3D(.18,.42,.11),id=="ice"?Color.FromRgb(45,105,153):cloak);}
            if(level>=3){for(int side=-1;side<=1;side+=2){AddEllipsoid(torso,new Point3D(.22,1.54,side*.25),new Vector3D(.07,.08,.055),magic);AddCone(torso,new Point3D(-.31,.77,side*.18),new Point3D(-.48,.53,side*.25),.055,lightTrim);}}
            model.Children.Add(torso);

            Model3DGroup head=new Model3DGroup();rig.Head=NewRigRotation();head.Transform=new RotateTransform3D(rig.Head,new Point3D(.035,1.97,0));AddEllipsoid(head,new Point3D(.04,1.98,0),new Vector3D(.24,.27,.22),skin);AddEllipsoid(head,new Point3D(.18,1.91,0),new Vector3D(.13,.11,.16),skin);AddEllipsoid(head,new Point3D(.255,1.94,0),new Vector3D(.07,.05,.075),Color.FromRgb(102,67,53));
            for(int side=-1;side<=1;side+=2){double z=side*.12;AddEllipsoid(head,new Point3D(.18,2.07,z),new Vector3D(.074,.054,.060),Color.FromRgb(37,32,36));ScaleTransform3D eye=AddAnimatedEllipsoid(head,new Point3D(.233,2.07,z),new Vector3D(.035,.027,.024),id=="ice"?Color.FromRgb(75,151,210):id=="dwarf"?Color.FromRgb(208,91,49):Color.FromRgb(81,137,119));if(side<0)rig.LeftEyeScale=eye;else rig.RightEyeScale=eye;AddEllipsoid(head,new Point3D(.258,2.07,z),new Vector3D(.014,.022,.014),Color.FromRgb(17,18,20));}
            AddEllipsoid(head,new Point3D(-.005,2.20,0),new Vector3D(.25,.12,.25),hair);AddEllipsoid(head,new Point3D(.09,2.16,0),new Vector3D(.19,.12,.24),hair);
            if(id=="gondor"){for(int i=0;i<5;i++){double z=(i-2)*.085;AddCone(head,new Point3D(-.07,2.17,z),new Point3D(-.26-(i%2)*.06,2.37,z),.085,hair);}AddEllipsoid(head,new Point3D(.03,2.13,.22),new Vector3D(.22,.035,.035),accent);if(level>=4){AddCone(head,new Point3D(-.02,2.23,.16),new Point3D(-.10,2.51,.27),.08,Color.FromRgb(25,17,33));AddCone(head,new Point3D(-.02,2.23,-.16),new Point3D(-.10,2.51,-.27),.08,Color.FromRgb(25,17,33));}}
            else if(id=="elf"){AddCone(head,new Point3D(-.02,2.16,-.16),new Point3D(-.24,2.36,-.24),.08,hair);AddCone(head,new Point3D(.02,2.17,.08),new Point3D(-.10,2.39,.14),.075,hair);AddEllipsoid(head,new Point3D(.05,2.26,0),new Vector3D(.24,.045,.22),accent);}
            else if(id=="dwarf"){for(int i=0;i<5;i++){double z=(i-2)*.085;AddCone(head,new Point3D(-.08,2.16,z),new Point3D(-.27,2.34+(i%2)*.05,z),.085,hair);}AddEllipsoid(head,new Point3D(.02,2.13,0),new Vector3D(.28,.045,.24),accent);}
            else if(id=="aura"){AddEllipsoid(head,new Point3D(-.16,1.99,.19),new Vector3D(.12,.35,.10),hair);AddEllipsoid(head,new Point3D(-.16,1.99,-.19),new Vector3D(.12,.35,.10),hair);AddCone(head,new Point3D(-.06,2.17,.16),new Point3D(-.26,2.34,.25),.065,hair);}
            else{AddEllipsoid(head,new Point3D(.04,2.25,0),new Vector3D(.22,.045,.23),accent);AddCone(head,new Point3D(.08,2.21,.20),new Point3D(.20,2.40,.21),.045,lightTrim);AddCone(head,new Point3D(.08,2.21,-.20),new Point3D(.20,2.40,-.21),.045,lightTrim);AddEllipsoid(head,new Point3D(-.13,1.99,.19),new Vector3D(.10,.25,.075),hair);AddEllipsoid(head,new Point3D(-.13,1.99,-.19),new Vector3D(.10,.25,.075),hair);}
            AddHeroHeadDetails(head,id,level,hair,accent,magic,lightTrim);model.Children.Add(head);
            rig.LeftHip=NewRigRotation();rig.RightHip=NewRigRotation();rig.LeftElbow=NewRigRotation();rig.RightElbow=NewRigRotation();AddHumanoidLeg(model,rig.LeftHip,NewRigRotation(),-1,cloth,armor,accent);AddHumanoidLeg(model,rig.RightHip,NewRigRotation(),1,cloth,armor,accent);rig.LeftShoulder=NewRigRotation();rig.RightShoulder=NewRigRotation();rig.LeftElbow=NewRigRotation();rig.RightElbow=NewRigRotation();AddTowerArm(model,rig.LeftShoulder,rig.LeftElbow,-1,skin,cloth,armor,accent,magic,id);AddTowerArm(model,rig.RightShoulder,rig.RightElbow,1,skin,cloth,armor,accent,magic,id);AddHeroUpgradeDetails(model,id,level,cloak,accent,magic,lightTrim);
            if(level>=2){Model3DGroup mantle=new Model3DGroup();rig.AuraRotation=new AxisAngleRotation3D(new Vector3D(0,1,0),0);mantle.Transform=new RotateTransform3D(rig.AuraRotation,new Point3D(0,1.33,0));AddEnergyArc(mantle,1.29,.58,.43,.045,.15,5.15,Color.FromArgb(205,magic.R,magic.G,magic.B));AddEnergyArc(mantle,1.57,.49,.38,.026,2.35,6.05,Color.FromArgb(175,lightTrim.R,lightTrim.G,lightTrim.B));if(level>=4){AddEnergyArc(mantle,1.83,.39,.31,.032,3.10,6.12,Color.FromArgb(188,magic.R,magic.G,magic.B));AddEllipsoid(mantle,new Point3D(.33,1.73,.28),new Vector3D(.10,.10,.10),lightTrim);}model.Children.Add(mantle);}
        }
        private void AddCloakMesh(Model3DGroup parent,Color cloak,Color trim,int level,TowerModel3D rig)
        {
            Model3DGroup cape=new Model3DGroup();rig.CapeRotation=NewRigRotation();cape.Transform=new RotateTransform3D(rig.CapeRotation,new Point3D(-.18,1.68,0));const int columns=10,rows=6;MeshGeometry3D mesh=new MeshGeometry3D();
            for(int row=0;row<=rows;row++){double v=(double)row/rows,y=1.69-v*1.42,width=.25+v*(level>=3?.34:.25),back=-.23-Math.Sin(v*Math.PI)*.21;for(int col=0;col<=columns;col++){double u=(double)col/columns,z=(u-.5)*2*width,fold=Math.Sin(u*Math.PI*10+v*2.2)*(.012+v*.024);mesh.Positions.Add(new Point3D(back+fold,y,z));Vector3D normal=new Vector3D(-.34,0,1);normal.Normalize();mesh.Normals.Add(normal);mesh.TextureCoordinates.Add(new Point(u,v));}}
            for(int row=0;row<rows;row++)for(int col=0;col<columns;col++){int a=row*(columns+1)+col,b=a+1,c=a+columns+1,d=c+1;mesh.TriangleIndices.Add(a);mesh.TriangleIndices.Add(c);mesh.TriangleIndices.Add(b);mesh.TriangleIndices.Add(b);mesh.TriangleIndices.Add(c);mesh.TriangleIndices.Add(d);}mesh.Freeze();Material material=Material3D(cloak);GeometryModel3D clothModel=new GeometryModel3D(mesh,material){BackMaterial=material};clothModel.Freeze();cape.Children.Add(clothModel);
            for(int side=-1;side<=1;side+=2){AddCone(cape,new Point3D(-.25,1.65,side*.27),new Point3D(-.40,.28,side*(level>=3?.62:.50)),.020,trim);if(level>=2){AddEllipsoid(cape,new Point3D(-.37,.52,side*.47),new Vector3D(.052,.085,.034),trim);AddEllipsoid(cape,new Point3D(-.34,.85,side*.43),new Vector3D(.032,.10,.024),Color.FromRgb(226,200,145));}}
            if(level>=3)for(int side=-1;side<=1;side+=2){AddEllipsoid(cape,new Point3D(-.40,.42,side*.39),new Vector3D(.05,.07,.025),Color.FromRgb(242,218,157));}
            parent.Children.Add(cape);
        }
        private void AddHeroTorsoDetails(Model3DGroup torso,string id,int level,Color cloth,Color cloak,Color armor,Color accent,Color magic,Color trim)
        {
            Color plate=id=="elf"?Color.FromRgb(215,224,206):id=="ice"?Color.FromRgb(113,158,187):id=="aura"?Color.FromRgb(111,48,83):id=="dwarf"?Color.FromRgb(54,39,43):Color.FromRgb(35,34,41);
            Point[] breastplate={new Point(-.22,1.58),new Point(-.12,1.72),new Point(.18,1.70),new Point(.29,1.55),new Point(.23,1.22),new Point(-.12,1.21),new Point(-.25,1.40)};
            AddArmorPlate(torso,breastplate,.365,.065,plate);for(int i=0;i<breastplate.Length;i++){Point a=breastplate[i],b=breastplate[(i+1)%breastplate.Length];AddCone(torso,new Point3D(a.X,a.Y,.384),new Point3D(b.X,b.Y,.384),.010,trim);}
            AddEllipsoid(torso,new Point3D(.055,1.06,.315),new Vector3D(.31,.050,.045),id=="elf"?Color.FromRgb(44,108,76):id=="ice"?Color.FromRgb(201,218,224):id=="gondor"?Color.FromRgb(142,39,49):accent);
            AddEllipsoid(torso,new Point3D(.08,1.06,.366),new Vector3D(.105,.078,.035),trim);
            if(id=="gondor")
            {
                AddArmorPlate(torso,new[]{new Point(-.04,1.55),new Point(.055,1.66),new Point(.15,1.55),new Point(.055,1.43)},.413,.025,Color.FromRgb(173,47,50));
                AddEllipsoid(torso,new Point3D(.03,1.47,.44),new Vector3D(.034,.034,.020),Color.FromRgb(244,209,145));
                if(level>=2){AddEllipsoid(torso,new Point3D(-.30,1.55,.14),new Vector3D(.095,.18,.10),Color.FromRgb(120,39,47));AddEllipsoid(torso,new Point3D(-.27,1.53,.22),new Vector3D(.055,.12,.035),Color.FromRgb(39,34,43));}
            }
            else if(id=="elf")
            {
                AddArmorPlate(torso,new[]{new Point(-.02,1.60),new Point(.20,1.52),new Point(.18,1.43),new Point(-.04,1.50)},.418,.025,Color.FromRgb(49,124,87));
                AddEllipsoid(torso,new Point3D(.105,1.48,.448),new Vector3D(.048,.052,.024),Color.FromRgb(224,192,99));
                for(int i=0;i<3;i++)AddEllipsoid(torso,new Point3D(-.20+i*.17,1.74,.22),new Vector3D(.075,.045,.055),i==1?Color.FromRgb(220,199,131):Color.FromRgb(99,156,119));
            }
            else if(id=="dwarf")
            {
                for(int i=0;i<5;i++)AddEllipsoid(torso,new Point3D(-.21+i*.13,1.72,.32),new Vector3D(.025,.025,.025),i%2==0?Color.FromRgb(237,150,76):Color.FromRgb(222,196,133));
                AddArmorPlate(torso,new[]{new Point(-.24,1.22),new Point(-.10,1.12),new Point(.20,1.16),new Point(.26,1.28),new Point(.16,1.32),new Point(-.18,1.31)},.421,.030,Color.FromRgb(160,48,43));
                if(level>=2)for(int side=-1;side<=1;side+=2)AddCone(torso,new Point3D(-.12,1.72,side*.22),new Point3D(-.27,1.98,side*.24),.105,Color.FromRgb(216,83,45));
            }
            else if(id=="aura")
            {
                AddEllipsoid(torso,new Point3D(.09,1.50,.423),new Vector3D(.08,.09,.035),magic);
                for(int i=0;i<3;i++){double z=.33+i*.025;AddEllipsoid(torso,new Point3D(.03,1.30-i*.11,z),new Vector3D(.18,.018,.025),Color.FromRgb(218,106,159));}
                for(int i=0;i<3;i++){double a=i*2.094;AddMagicEllipsoid(torso,new Point3D(.22,1.45+Math.Sin(a)*.12,.39+Math.Cos(a)*.02),new Vector3D(.045,.048,.028),Color.FromRgb(252,167,201));}
            }
            else
            {
                AddArmorPlate(torso,new[]{new Point(-.03,1.61),new Point(.16,1.66),new Point(.22,1.50),new Point(.02,1.45)},.423,.026,Color.FromRgb(143,185,207));
                AddEllipsoid(torso,new Point3D(.11,1.51,.455),new Vector3D(.052,.062,.025),Color.FromRgb(231,246,251));
                for(int side=-1;side<=1;side+=2){AddCone(torso,new Point3D(-.20,1.62,side*.18),new Point3D(-.32,1.86,side*.23),.075,Color.FromRgb(179,216,232));}
            }
            if(level>=1)
            {
                for(int side=-1;side<=1;side+=2){double z=side*.34;AddEllipsoid(torso,new Point3D(-.01,1.70,z),new Vector3D(.23,.17,.14),armor);AddEllipsoid(torso,new Point3D(.13,1.73,z+side*.065),new Vector3D(.09,.07,.055),trim);}
            }
            if(level>=2)
            {
                AddEllipsoid(torso,new Point3D(.15,1.13,.347),new Vector3D(.07,.10,.035),magic);for(int i=0;i<3;i++)AddCone(torso,new Point3D(.18,1.18-i*.06,.38),new Point3D(.28,1.24-i*.06,.40),.018,trim);
                if(id=="aura"){AddEllipsoid(torso,new Point3D(-.31,1.33,.10),new Vector3D(.11,.23,.08),Color.FromRgb(160,69,112));AddEllipsoid(torso,new Point3D(-.31,1.33,-.10),new Vector3D(.11,.23,.08),Color.FromRgb(160,69,112));}
            }
            if(level>=3)
            {
                for(int side=-1;side<=1;side+=2){AddEllipsoid(torso,new Point3D(.04,1.84,side*.24),new Vector3D(.11,.07,.06),magic);AddCone(torso,new Point3D(-.16,.93,side*.18),new Point3D(-.32,.68,side*.28),.06,trim);}
            }
        }
        private void AddHeroHeadDetails(Model3DGroup head,string id,int level,Color hair,Color accent,Color magic,Color trim)
        {
            if(id=="gondor")
            {
                AddEllipsoid(head,new Point3D(.01,2.16,.255),new Vector3D(.27,.042,.038),Color.FromRgb(168,43,46));
                for(int i=0;i<7;i++){double z=(i-3)*.064;AddCone(head,new Point3D(-.015,2.20,z),new Point3D(-.17-(i%3)*.055,2.42+(i%2)*.035,z),.064,i%3==0?Color.FromRgb(52,40,45):hair);}
                AddEllipsoid(head,new Point3D(.11,2.04,.216),new Vector3D(.12,.025,.026),Color.FromRgb(218,73,66));
            }
            else if(id=="elf")
            {
                for(int i=0;i<8;i++){double z=(i-3.5)*.057;AddCone(head,new Point3D(-.08,2.22,z),new Point3D(-.20-(i%3)*.04,2.43+(i%2)*.035,z),.057,i%3==0?Color.FromRgb(41,54,61):hair);}
                AddEllipsoid(head,new Point3D(.035,2.28,.238),new Vector3D(.235,.035,.035),Color.FromRgb(215,184,104));AddEllipsoid(head,new Point3D(.12,2.29,.27),new Vector3D(.045,.045,.022),Color.FromRgb(80,165,113));
                if(level>=3)for(int side=-1;side<=1;side+=2)AddCone(head,new Point3D(-.10,2.27,side*.16),new Point3D(-.18,2.57,side*.23),.05,Color.FromRgb(202,225,186));
            }
            else if(id=="dwarf")
            {
                AddEllipsoid(head,new Point3D(-.01,2.22,.22),new Vector3D(.26,.045,.035),Color.FromRgb(163,45,41));
                for(int i=0;i<7;i++){double z=(i-3)*.065;AddCone(head,new Point3D(-.02,2.21,z),new Point3D(-.18-(i%2)*.05,2.48+(i%3)*.025,z),.07,i%2==0?hair:Color.FromRgb(139,43,38));}
                AddEllipsoid(head,new Point3D(.09,1.87,.20),new Vector3D(.17,.105,.055),Color.FromRgb(122,49,43));
            }
            else if(id=="aura")
            {
                AddEllipsoid(head,new Point3D(-.07,2.28,.02),new Vector3D(.55,.075,.48),Color.FromRgb(43,30,52));
                AddCone(head,new Point3D(-.12,2.27,0),new Point3D(-.28,2.65,0),.31,Color.FromRgb(55,33,63));
                AddEllipsoid(head,new Point3D(-.01,2.31,.24),new Vector3D(.32,.052,.045),Color.FromRgb(151,65,112));
                for(int side=-1;side<=1;side+=2){for(int i=0;i<3;i++)AddEllipsoid(head,new Point3D(-.10-i*.06,1.95-i*.18,side*.19),new Vector3D(.09,.20,.075),i==2?Color.FromRgb(225,123,166):hair);}
                for(int i=0;i<3;i++){double z=(i-1)*.11;AddMagicEllipsoid(head,new Point3D(.16,2.31,z+.28),new Vector3D(.05,.055,.032),Color.FromRgb(245,143,185));}
            }
            else
            {
                AddEllipsoid(head,new Point3D(.02,2.27,.22),new Vector3D(.25,.055,.05),Color.FromRgb(217,227,232));
                AddEllipsoid(head,new Point3D(.10,2.31,.255),new Vector3D(.075,.075,.035),Color.FromRgb(150,198,218));
                for(int side=-1;side<=1;side+=2){for(int i=0;i<4;i++){AddCone(head,new Point3D(-.10,2.19-i*.10,side*(.17+i*.012)),new Point3D(-.22-i*.035,2.42-i*.11,side*(.20+i*.014)),.055,Color.FromRgb((byte)(198-i*5),(byte)(214-i*4),(byte)(222-i*3)));}}
                if(level>=3)for(int side=-1;side<=1;side+=2)AddCone(head,new Point3D(-.06,2.31,side*.19),new Point3D(-.13,2.58,side*.27),.045,trim);
            }
            if(level>=2){AddEllipsoid(head,new Point3D(.27,2.03,.12),new Vector3D(.025,.025,.025),magic);AddEllipsoid(head,new Point3D(.27,2.03,-.12),new Vector3D(.025,.025,.025),magic);}
        }
        private void AddHeroUpgradeDetails(Model3DGroup model,string id,int level,Color cloak,Color accent,Color magic,Color trim)
        {
            if(level>=1){for(int side=-1;side<=1;side+=2){AddEllipsoid(model,new Point3D(-.02,1.77,side*.41),new Vector3D(.24,.16,.095),trim);AddEllipsoid(model,new Point3D(.08,1.78,side*.45),new Vector3D(.11,.08,.045),magic);}}
            if(level>=2)
            {
                if(id=="gondor"){for(int side=-1;side<=1;side+=2){AddCone(model,new Point3D(-.28,1.68,side*.27),new Point3D(-.53,1.84,side*.38),.10,Color.FromRgb(46,31,40));AddEllipsoid(model,new Point3D(-.22,1.70,side*.36),new Vector3D(.06,.06,.035),Color.FromRgb(189,48,52));}}
                else if(id=="elf"){AddEnergyArc(model,1.69,.50,.39,.026,.25,2.88,Color.FromArgb(165,188,248,198));AddEllipsoid(model,new Point3D(-.27,1.72,.05),new Vector3D(.17,.19,.10),Color.FromRgb(58,110,76));}
                else if(id=="dwarf"){for(int i=0;i<4;i++)AddCone(model,new Point3D(-.23,1.28,(i-1.5)*.16),new Point3D(-.43,1.42+(i%2)*.08,(i-1.5)*.17),.055,Color.FromRgb(230,98,43));}
                else if(id=="aura"){AddEnergyArc(model,1.62,.38,.29,.022,.3,5.7,Color.FromArgb(175,239,123,175));}
                else{AddEnergyArc(model,1.68,.45,.35,.025,.15,2.75,Color.FromArgb(170,145,220,246));}
            }
            if(level>=3)
            {
                for(int side=-1;side<=1;side+=2){double z=side*.30;AddArmorPlate(model,new[]{new Point(-.29,1.68),new Point(-.55,1.92),new Point(-.12,1.81),new Point(.02,1.69)},z+.07,.04,id=="ice"?Color.FromRgb(141,190,212):id=="elf"?Color.FromRgb(111,164,121):cloak);AddEllipsoid(model,new Point3D(-.30,1.78,z+.085),new Vector3D(.07,.07,.04),trim);}
            }
            if(level>=4)
            {
                if(id=="gondor"){for(int side=-1;side<=1;side+=2){AddCone(model,new Point3D(-.23,2.05,side*.18),new Point3D(-.18,2.43,side*.30),.095,Color.FromRgb(27,21,31));AddEnergyArc(model,1.47,.67,.52,.035,2.9,6.15,Color.FromArgb(180,190,42,53));}}
                else if(id=="elf"){AddEnergyArc(model,2.01,.48,.37,.026,.05,3.02,Color.FromArgb(185,206,251,211));AddEllipsoid(model,new Point3D(-.35,1.53,.08),new Vector3D(.15,.24,.06),Color.FromRgb(155,203,159));}
                else if(id=="dwarf"){for(int i=0;i<5;i++){double z=(i-2)*.18;AddCone(model,new Point3D(-.25,1.36,z),new Point3D(-.58,1.55+(i%2)*.13,z),.085,Color.FromRgb(255,103,37));}AddEnergyArc(model,1.45,.57,.46,.042,3.0,6.1,Color.FromArgb(170,255,155,56));}
                else if(id=="aura"){AddEnergyArc(model,2.0,.51,.41,.025,.15,6.0,Color.FromArgb(180,248,149,196));for(int i=0;i<4;i++)AddMagicEllipsoid(model,new Point3D(-.27+i*.18,1.72,.34),new Vector3D(.045,.045,.035),Color.FromRgb(254,194,218));}
                else{for(int side=-1;side<=1;side+=2)AddCone(model,new Point3D(-.25,1.59,side*.25),new Point3D(-.64,1.82,side*.33),.09,Color.FromRgb(168,224,242));AddEnergyArc(model,1.62,.65,.48,.036,.1,3.0,Color.FromArgb(190,148,231,250));}
            }
        }
        private void AddArmorPlate(Model3DGroup group,Point[] outline,double frontZ,double thickness,Color color)
        {
            if(outline==null||outline.Length<3)return;MeshGeometry3D mesh=new MeshGeometry3D();int n=outline.Length;double cx=0,cy=0;for(int i=0;i<n;i++){cx+=outline[i].X;cy+=outline[i].Y;}cx/=n;cy/=n;
            for(int i=0;i<n;i++){mesh.Positions.Add(new Point3D(outline[i].X,outline[i].Y,frontZ));mesh.Normals.Add(new Vector3D(0,0,1));mesh.TextureCoordinates.Add(new Point((outline[i].X+1)*.5,outline[i].Y/2.8));}
            for(int i=0;i<n;i++){mesh.Positions.Add(new Point3D(outline[i].X,outline[i].Y,frontZ-thickness));mesh.Normals.Add(new Vector3D(0,0,-1));mesh.TextureCoordinates.Add(new Point((outline[i].X+1)*.5,outline[i].Y/2.8));}
            int fc=mesh.Positions.Count;mesh.Positions.Add(new Point3D(cx,cy,frontZ));mesh.Normals.Add(new Vector3D(0,0,1));mesh.TextureCoordinates.Add(new Point(.5,cy/2.8));int bc=mesh.Positions.Count;mesh.Positions.Add(new Point3D(cx,cy,frontZ-thickness));mesh.Normals.Add(new Vector3D(0,0,-1));mesh.TextureCoordinates.Add(new Point(.5,cy/2.8));
            for(int i=0;i<n;i++){int j=(i+1)%n;mesh.TriangleIndices.Add(fc);mesh.TriangleIndices.Add(i);mesh.TriangleIndices.Add(j);mesh.TriangleIndices.Add(bc);mesh.TriangleIndices.Add(n+j);mesh.TriangleIndices.Add(n+i);mesh.TriangleIndices.Add(i);mesh.TriangleIndices.Add(n+i);mesh.TriangleIndices.Add(j);mesh.TriangleIndices.Add(j);mesh.TriangleIndices.Add(n+i);mesh.TriangleIndices.Add(n+j);}
            mesh.Freeze();Material mat=Material3D(color);GeometryModel3D plate=new GeometryModel3D(mesh,mat){BackMaterial=mat};plate.Freeze();group.Children.Add(plate);
        }
        private void AddEnergyArc(Model3DGroup group,double centerY,double radiusX,double radiusZ,double tube,double start,double end,Color color)
        {
            const int segments=42,sides=7;MeshGeometry3D mesh=new MeshGeometry3D();
            for(int i=0;i<=segments;i++){double theta=start+(end-start)*i/segments,ct=Math.Cos(theta),st=Math.Sin(theta);for(int j=0;j<=sides;j++){double phi=2*Math.PI*j/sides,cp=Math.Cos(phi),sp=Math.Sin(phi),rrx=radiusX+tube*cp,rrz=radiusZ+tube*cp;mesh.Positions.Add(new Point3D(rrx*ct,centerY+tube*sp,rrz*st));Vector3D normal=new Vector3D(cp*ct,sp,cp*st);normal.Normalize();mesh.Normals.Add(normal);}}
            for(int i=0;i<segments;i++)for(int j=0;j<sides;j++){int a=i*(sides+1)+j,b=a+sides+1;mesh.TriangleIndices.Add(a);mesh.TriangleIndices.Add(b);mesh.TriangleIndices.Add(a+1);mesh.TriangleIndices.Add(a+1);mesh.TriangleIndices.Add(b);mesh.TriangleIndices.Add(b+1);}
            mesh.Freeze();Material material=Emissive3D(color);GeometryModel3D arc=new GeometryModel3D(mesh,material){BackMaterial=material};arc.Freeze();group.Children.Add(arc);
        }
        private void AddTowerArm(Model3DGroup root,AxisAngleRotation3D shoulderRotation,AxisAngleRotation3D elbowRotation,int side,Color skin,Color cloth,Color armor,Color trim,Color magic,string id)
        {
            double z=side*.34;Model3DGroup upper=new Model3DGroup();upper.Transform=new RotateTransform3D(shoulderRotation,new Point3D(0,1.72,z));AddEllipsoid(upper,new Point3D(0,1.65,z+side*.04),new Vector3D(.20,.19,.20),armor);AddEllipsoid(upper,new Point3D(.015,1.45,z+side*.08),new Vector3D(.135,.29,.13),skin);Model3DGroup lower=new Model3DGroup();lower.Transform=new RotateTransform3D(elbowRotation,new Point3D(.015,1.25,z+side*.08));AddEllipsoid(lower,new Point3D(.06,1.22,z+side*.08),new Vector3D(.135,.25,.12),cloth);AddEllipsoid(lower,new Point3D(.10,1.00,z+side*.08),new Vector3D(.14,.10,.12),trim);AddEllipsoid(lower,new Point3D(.20,.91,z+side*.08),new Vector3D(.14,.12,.11),skin);
            if(side>0){Point3D hand=new Point3D(.32,.91,z+side*.08);if(id=="gondor"){AddEllipsoid(lower,new Point3D(.39,.91,z+side*.08),new Vector3D(.28,.055,.045),Color.FromRgb(30,25,33));AddEllipsoid(lower,new Point3D(.35,.91,z+side*.08),new Vector3D(.07,.10,.09),trim);AddArmorPlate(lower,new[]{new Point(.48,.82),new Point(.72,.79),new Point(1.17,.89),new Point(.81,.96),new Point(.50,.96)},z+side*.15,.065,Color.FromRgb(40,35,46));AddCone(lower,new Point3D(.53,.84,z+side*.16),new Point3D(1.12,.90,z+side*.16),.021,Color.FromRgb(173,43,49));AddEllipsoid(lower,new Point3D(.55,.91,z+side*.13),new Vector3D(.08,.10,.075),Color.FromRgb(164,48,50));}
                else if(id=="elf"){AddMagicEllipsoid(lower,hand,new Vector3D(.13,.14,.13),magic);for(int i=0;i<3;i++)AddCone(lower,new Point3D(hand.X-.08,hand.Y-.05+i*.07,hand.Z),new Point3D(hand.X+.20,hand.Y+.06+i*.07,hand.Z),.025,magic);}
                else if(id=="dwarf"){AddEllipsoid(lower,new Point3D(hand.X,hand.Y,hand.Z),new Vector3D(.22,.16,.18),trim);AddMagicEllipsoid(lower,new Point3D(hand.X+.16,hand.Y+.02,hand.Z),new Vector3D(.13,.13,.13),magic);for(int i=0;i<3;i++)AddCone(lower,new Point3D(hand.X+.08,hand.Y,hand.Z+(i-1)*.07),new Point3D(hand.X+.27,hand.Y+.18+i*.025,hand.Z+(i-1)*.09),.045,magic);}
                else if(id=="aura"){AddMagicEllipsoid(lower,new Point3D(hand.X+.07,hand.Y+.02,hand.Z),new Vector3D(.10,.10,.10),magic);for(int i=0;i<3;i++)AddCone(lower,new Point3D(hand.X+.05,hand.Y-.08+i*.07,hand.Z),new Point3D(hand.X+.40,hand.Y+.12+i*.05,hand.Z+(i-1)*.09),.018,magic);}
                else{AddEllipsoid(lower,new Point3D(hand.X+.08,hand.Y,hand.Z),new Vector3D(.08,.12,.09),trim);AddEllipsoid(lower,new Point3D(hand.X+.14,hand.Y+.02,hand.Z),new Vector3D(.055,.055,.055),magic);AddCone(lower,new Point3D(hand.X+.08,hand.Y+.06,hand.Z),new Point3D(hand.X+.62,hand.Y+.48,hand.Z),.075,Color.FromRgb(204,231,243));AddCone(lower,new Point3D(hand.X+.62,hand.Y+.48,hand.Z),new Point3D(hand.X+.72,hand.Y+.58,hand.Z),.12,magic);}
            }
            else if(id=="elf"){AddArmorPlate(lower,new[]{new Point(-.13,.81),new Point(.04,.78),new Point(.10,1.10),new Point(-.09,1.14)},z-side*.12,.07,Color.FromRgb(52,101,74));AddArmorPlate(lower,new[]{new Point(-.09,.87),new Point(.02,.86),new Point(.06,1.06),new Point(-.06,1.08)},z-side*.19,.025,Color.FromRgb(203,185,126));}
            upper.Children.Add(lower);root.Children.Add(upper);
        }
        private void RebuildTowerModel(Tower tower){RemoveTowerModel(tower);tower.Model=CreateTowerModel(tower);if(tower.Model!=null&&worldView!=null)worldView.Children.Add(tower.Model.Visual);}
        private void RemoveTowerModel(Tower tower){if(tower!=null&&tower.Model!=null&&worldView!=null)worldView.Children.Remove(tower.Model.Visual);if(tower!=null)tower.Model=null;}
        private void ClearTowerModels(){if(towers==null)return;foreach(Tower tower in towers)RemoveTowerModel(tower);}
        private void UpdateTowerModels()
        {
            foreach(Tower tower in towers){TowerModel3D rig=tower.Model;if(rig==null)continue;double age=clock-tower.LastShot,pose=AttackPose(age),idle=Math.Sin(clock*2.4+rig.Phase),scale=112*MapScale/(rig.HeightNorm*.848);if(tower.Level>=3)scale*=1.035;double breath=1+Math.Sin(clock*3.1+rig.Phase)*.003;rig.ScaleTransform.ScaleX=scale*breath;rig.ScaleTransform.ScaleY=scale*(1+Math.Sin(clock*3.1+rig.Phase+1)*.004);rig.ScaleTransform.ScaleZ=scale*breath;rig.PositionTransform.OffsetX=tower.X;rig.PositionTransform.OffsetY=TerrainHeight(tower.X,tower.Y);rig.PositionTransform.OffsetZ=tower.Y*groundDepthScale;if(tower.LastShot>-1&&age<1.5)rig.Yaw.Angle=-Math.Atan2(tower.LastTargetY-tower.Y,tower.LastTargetX-tower.X)*180/Math.PI;
                double swing=tower.Type.Id=="gondor"?112:tower.Type.Id=="elf"?78:tower.Type.Id=="dwarf"?96:tower.Type.Id=="aura"?44:84;rig.Torso.Angle=idle*1.25+pose*(tower.Type.Id=="gondor"?-7:tower.Type.Id=="elf"?5:4);rig.Head.Angle=Math.Sin(clock*1.6+rig.Phase)*3.2+pose*5.5;rig.LeftShoulder.Angle=Math.Sin(clock*1.9+rig.Phase)*5-(tower.Type.Id=="aura"?Math.Sin(clock*2.5+rig.Phase)*13:pose*(tower.Type.Id=="gondor"?28:12));rig.RightShoulder.Angle=Math.Sin(clock*2.2+rig.Phase+1)*5+pose*swing;rig.LeftElbow.Angle=13+Math.Max(0,Math.Sin(clock*1.9+rig.Phase))*10+pose*18;rig.RightElbow.Angle=14+Math.Max(0,pose)*38;rig.LeftHip.Angle=Math.Sin(clock*2.0+rig.Phase)*2.7;rig.RightHip.Angle=-rig.LeftHip.Angle;if(rig.CapeRotation!=null)rig.CapeRotation.Angle=Math.Sin(clock*2.1+rig.Phase)*5+pose*(tower.Type.Id=="gondor"?18:-8);if(rig.AuraRotation!=null)rig.AuraRotation.Angle=clock*(28+tower.Level*5)+rig.Phase;
                double blink=Math.Pow(Math.Max(0,Math.Sin((clock+rig.Phase)*.73)),24);if(rig.LeftEyeScale!=null)rig.LeftEyeScale.ScaleY=.027*(1-.92*blink);if(rig.RightEyeScale!=null)rig.RightEyeScale.ScaleY=.027*(1-.92*blink);
            }
        }
        private BoltModel3D CreateBoltModel(string id)
        {
            BoltModel3D rig=new BoltModel3D{TypeId=id};Model3DGroup model=new Model3DGroup();rig.ScaleTransform=new ScaleTransform3D(1,1,1);rig.Yaw=new AxisAngleRotation3D(new Vector3D(0,1,0),0);rig.Spin=new AxisAngleRotation3D(new Vector3D(1,0,0),0);rig.PositionTransform=new TranslateTransform3D();Transform3DGroup transform=new Transform3DGroup();transform.Children.Add(rig.ScaleTransform);transform.Children.Add(new RotateTransform3D(rig.Yaw));transform.Children.Add(new RotateTransform3D(rig.Spin));transform.Children.Add(rig.PositionTransform);rig.Visual=new ModelVisual3D{Content=model,Transform=transform};
            if(id=="gondor"){AddMagicEllipsoid(model,new Point3D(-.08,0,0),new Vector3D(.66,.38,.47),Color.FromRgb(22,17,31));AddEllipsoid(model,new Point3D(.30,.02,0),new Vector3D(.45,.25,.34),Color.FromRgb(47,37,54));AddCone(model,new Point3D(.18,.02,.18),new Point3D(1.08,.17,.04),.25,Color.FromRgb(25,19,32));AddCone(model,new Point3D(.10,-.04,-.22),new Point3D(.79,-.28,-.04),.19,Color.FromRgb(95,26,43));AddMagicEllipsoid(model,new Point3D(-.34,.20,.20),new Vector3D(.18,.12,.09),Color.FromRgb(232,56,67));AddEnergyArc(model,-.02,.84,.48,.065,.45,5.68,Color.FromArgb(216,124,33,56));}
            else if(id=="elf"){AddMagicEllipsoid(model,new Point3D(.05,0,0),new Vector3D(.39,.34,.38),Color.FromRgb(233,255,244));AddEllipsoid(model,new Point3D(-.36,0,0),new Vector3D(.46,.18,.24),Color.FromRgb(150,233,189));for(int i=0;i<3;i++){double a=i*Math.PI*2/3;AddMagicEllipsoid(model,new Point3D(Math.Cos(a)*.48,Math.Sin(a)*.38,Math.Sin(a)*.39),new Vector3D(.17,.13,.14),Color.FromRgb(127,229,174));}AddEnergyArc(model,.02,.70,.58,.075,.25,5.92,Color.FromArgb(224,137,244,193));AddEnergyArc(model,.0,.49,.44,.04,1.65,6.1,Color.FromArgb(210,239,255,246));}
            else if(id=="dwarf"){AddMagicEllipsoid(model,new Point3D(.18,0,0),new Vector3D(.50,.43,.44),Color.FromRgb(255,124,30));AddMagicEllipsoid(model,new Point3D(.36,.03,.04),new Vector3D(.34,.31,.33),Color.FromRgb(255,226,95));AddEllipsoid(model,new Point3D(.43,.04,.05),new Vector3D(.18,.18,.19),Color.FromRgb(255,250,195));for(int i=0;i<5;i++){double a=i*Math.PI*.4;AddCone(model,new Point3D(-.20,Math.Cos(a)*.20,Math.Sin(a)*.22),new Point3D(-.75-(i%2)*.12,Math.Cos(a)*.43,Math.Sin(a)*.40),.15,Color.FromRgb(255,97,27));}AddEnergyArc(model,0,.57,.46,.07,.2,5.95,Color.FromArgb(225,255,171,51));}
            else if(id=="ice"){AddMagicEllipsoid(model,new Point3D(-.02,0,0),new Vector3D(.25,.28,.27),Color.FromRgb(215,250,255));AddCone(model,new Point3D(-.25,0,0),new Point3D(.84,0,0),.31,Color.FromRgb(131,220,248));AddCone(model,new Point3D(.10,.10,.02),new Point3D(-.35,.50,.12),.19,Color.FromRgb(234,253,255));AddCone(model,new Point3D(.08,-.12,-.02),new Point3D(-.39,-.45,-.12),.17,Color.FromRgb(99,190,231));AddCone(model,new Point3D(.0,.04,.10),new Point3D(.42,.31,.48),.14,Color.FromRgb(169,237,252));AddCone(model,new Point3D(-.04,-.06,-.12),new Point3D(.36,-.36,-.43),.13,Color.FromRgb(197,245,255));AddEnergyArc(model,0,.52,.47,.045,.55,5.45,Color.FromArgb(200,179,245,255));}
            else{AddMagicEllipsoid(model,new Point3D(0,0,0),new Vector3D(.32,.30,.32),Color.FromRgb(245,124,190));for(int i=0;i<3;i++){double a=i*Math.PI*2/3;AddMagicEllipsoid(model,new Point3D(Math.Cos(a)*.46,Math.Sin(a)*.38,Math.Sin(a)*.38),new Vector3D(.11,.10,.10),Color.FromRgb(255,214,238));}AddEnergyArc(model,0,.62,.42,.035,.20,5.8,Color.FromArgb(225,250,130,198));AddEnergyArc(model,.02,.44,.55,.025,1.1,6.05,Color.FromArgb(190,255,222,242));}
            return rig;
        }
        private void UpdateBoltModels()
        {
            foreach(Bolt bolt in bolts){BoltModel3D rig=bolt.Model;if(rig==null)continue;double dx=bolt.Target==null?1:bolt.Target.X-bolt.X,dy=bolt.Target==null?0:bolt.Target.Y-22*MapScale-bolt.Y;rig.Yaw.Angle=-Math.Atan2(dy,dx)*180/Math.PI;rig.Spin.Angle=clock*(rig.TypeId=="ice"?190:rig.TypeId=="gondor"?240:155)+bolt.Phase*45;double s=(rig.TypeId=="gondor"?13.5:14.5)*MapScale;rig.ScaleTransform.ScaleX=s;rig.ScaleTransform.ScaleY=s;rig.ScaleTransform.ScaleZ=s;rig.PositionTransform.OffsetX=bolt.X;rig.PositionTransform.OffsetY=TerrainHeight(bolt.X,bolt.Y)+18*MapScale;rig.PositionTransform.OffsetZ=bolt.Y*groundDepthScale;}
        }
        private void RemoveBoltModel(Bolt bolt){if(bolt!=null&&bolt.Model!=null&&worldView!=null)worldView.Children.Remove(bolt.Model.Visual);if(bolt!=null)bolt.Model=null;}
        private void ClearBoltModels(){if(bolts==null)return;foreach(Bolt bolt in bolts)RemoveBoltModel(bolt);}

        internal void RenderField(DrawingContext dc,double width,double height)
        {
            if(width<1||height<1)return;worldScale=Math.Min(width/WorldW,height/WorldH)*Zoom;offsetX=width*.5-viewCenterX*worldScale;offsetY=height*.5-viewCenterY*worldScale;ConfigureWorldCamera(width,height);BitmapSource scene=GetScene(arenaIndex);if(scene!=null&&groundVisual!=null&&groundScene!=arenaIndex){groundVisual.Content=BuildWorldGround(scene);groundScene=arenaIndex;}dc.PushTransform(new TranslateTransform(offsetX,offsetY));dc.PushTransform(new ScaleTransform(worldScale,worldScale));foreach(Tower t in towers)DrawTower(dc,t);DrawEnemyIndicators(dc);foreach(Burst b in bursts)DrawBurst(dc,b);if(selectedType!=null&&mouseWorld.X>=0)DrawPreview(dc,mouseWorld.X,mouseWorld.Y);dc.Pop();dc.Pop();
        }
        private BitmapSource GetScene(int scene){if(sceneCache==null||sceneCacheArena!=arenaIndex){DrawingGroup drawing=BuildScene(scene);DrawingVisual visual=new DrawingVisual();using(DrawingContext dc=visual.RenderOpen()){dc.PushTransform(new ScaleTransform(2,2));dc.DrawDrawing(drawing);dc.Pop();}RenderTargetBitmap bitmap=new RenderTargetBitmap(2048,2048,96,96,PixelFormats.Pbgra32);bitmap.Render(visual);bitmap.Freeze();sceneCache=bitmap;sceneCacheArena=arenaIndex;}return sceneCache;}
        private DrawingGroup BuildScene(int scene)
        {
            Color[] tops={Color.FromRgb(54,78,53),Color.FromRgb(80,57,42),Color.FromRgb(105,133,139)};Color[] bottoms={Color.FromRgb(80,98,57),Color.FromRgb(120,82,55),Color.FromRgb(153,168,165)};int biome=scene%3;Color top=tops[biome],bottom=bottoms[biome];DrawingGroup group=new DrawingGroup();using(DrawingContext dc=group.Open())
            {
                LinearGradientBrush ground=new LinearGradientBrush(top,bottom,72);ground.Freeze();dc.DrawRectangle(ground,null,new Rect(0,0,1024,1024));Random r=new Random(911+scene*37);
                for(int i=0;i<5200;i++){double x=r.NextDouble()*1024,y=r.NextDouble()*1024,len=(1.2+r.NextDouble()*5.2),angle=r.NextDouble()*Math.PI*2;byte alpha=(byte)(18+r.Next(0,29));Color c;if(biome==0)c=i%4==0?Color.FromArgb(alpha,177,177,106):Color.FromArgb(alpha,24,45,29);else if(biome==1)c=i%3==0?Color.FromArgb(alpha,215,147,85):Color.FromArgb(alpha,48,34,25);else c=i%3==0?Color.FromArgb(alpha,224,234,230):Color.FromArgb(alpha,71,91,91);dc.DrawLine(Stroke(c,.45+r.NextDouble()*.65),new Point(x,y),new Point(x+Math.Cos(angle)*len,y+Math.Sin(angle)*len));}
                for(int i=0;i<180;i++){double x=r.NextDouble()*1024,y=r.NextDouble()*1024,w=2+r.NextDouble()*6,h=1+r.NextDouble()*3;Color c=biome==0?Color.FromArgb(27,125,137,89):biome==1?Color.FromArgb(30,189,125,77):Color.FromArgb(37,220,232,226);dc.DrawEllipse(Frozen(c),null,new Point(x,y),w,h);}
                if(biome==0){for(int i=0;i<68;i++){double x=r.NextDouble()*1024,y=r.NextDouble()*1024;dc.DrawLine(Stroke(Color.FromArgb(36,197,189,109),.6),new Point(x,y),new Point(x+2,y-4));}}
                if(biome==2){for(int i=0;i<42;i++){double x=r.NextDouble()*1024,y=r.NextDouble()*1024;dc.DrawEllipse(Frozen(Color.FromArgb(33,242,246,242)),null,new Point(x,y),3,1.4);}}
            }group.Freeze();return group;
        }
        private bool NearPath(double x,double y,double margin){for(int i=1;i<motionPath.Length;i++)if(PointSegmentDistance(x,y,motionPath[i-1],motionPath[i])<margin)return true;return false;}
        private void DrawCanopyTree(DrawingContext dc,double x,double y,double h,int seed)
        {
            double r=h*.34;dc.DrawEllipse(Frozen(Color.FromArgb(55,12,22,15)),null,new Point(x+3,y+2),r*1.15,r*.32);Pen trunk=Stroke(Color.FromRgb(95,68,43),Math.Max(2,h*.065));dc.DrawLine(trunk,new Point(x,y+2),new Point(x,y-r*.78));dc.DrawLine(trunk,new Point(x,y-r*.44),new Point(x-r*.39,y-r*.74));dc.DrawLine(trunk,new Point(x,y-r*.48),new Point(x+r*.43,y-r*.72));
            Color[] shades={Color.FromRgb(27,68,48),Color.FromRgb(38,89,56),Color.FromRgb(52,111,64),Color.FromRgb(69,128,69)};dc.DrawGeometry(Frozen(shades[seed%4]),Stroke(Color.FromArgb(90,17,45,32),.8),BlobGeometry(x,y-r*.78,r*.78,r*.52,seed,13));dc.DrawGeometry(Frozen(shades[(seed+1)%4]),null,BlobGeometry(x-r*.34,y-r*.73,r*.48,r*.38,seed+5,9));dc.DrawGeometry(Frozen(shades[(seed+2)%4]),null,BlobGeometry(x+r*.33,y-r*.82,r*.46,r*.36,seed+9,9));DrawLeaf(dc,x-r*.24,y-r*1.04,r*.56,r*.21,-.35,Color.FromArgb(95,139,166,82));DrawLeaf(dc,x+r*.18,y-r*.92,r*.52,r*.2,.42,Color.FromArgb(82,155,178,89));
        }
        private void DrawCharredTree(DrawingContext dc,double x,double y,double h,int seed)
        {
            double r=h*.29;dc.DrawEllipse(Frozen(Color.FromArgb(70,16,12,9)),null,new Point(x+2,y+1),r*1.15,r*.38);Pen trunk=Stroke(Color.FromRgb(42,32,26),Math.Max(2,h*.07));dc.DrawLine(trunk,new Point(x,y),new Point(x+2,y-r*1.2));dc.DrawLine(trunk,new Point(x,y-r*.53),new Point(x-r*.55,y-r*.93));dc.DrawLine(trunk,new Point(x+1,y-r*.72),new Point(x+r*.58,y-r*1.04));dc.DrawLine(trunk,new Point(x,y-r*.92),new Point(x-r*.28,y-r*1.38));if(seed%2==0)dc.DrawEllipse(Frozen(Color.FromArgb(143,178,82,42)),null,new Point(x+r*.55,y-r*.94),2.5,2.5);
        }
        private void DrawSnowTree(DrawingContext dc,double x,double y,double h,int seed)
        {
            double r=h*.31;dc.DrawEllipse(Frozen(Color.FromArgb(60,32,53,61)),null,new Point(x+2,y+1),r*1.14,r*.32);dc.DrawLine(Stroke(Color.FromRgb(100,81,64),Math.Max(2,h*.055)),new Point(x,y),new Point(x,y-r));Brush[] greens={Frozen(Color.FromRgb(35,73,75)),Frozen(Color.FromRgb(49,91,88)),Frozen(Color.FromRgb(69,112,105))};for(int k=0;k<3;k++){double cy=y-r*(.35+k*.29),rr=r*(1-k*.16);dc.DrawGeometry(greens[k],null,BlobGeometry(x,cy,rr,rr*.57,seed+k*3,9));DrawLeaf(dc,x-rr*.12,cy-rr*.28,rr*.95,rr*.18,-.12,Color.FromArgb(205,217,232,226));}
        }
        private void DrawGroundClump(DrawingContext dc,double x,double y,double r,int scene,int seed)
        {
            if(scene==2){dc.DrawEllipse(Frozen(Color.FromArgb(55,26,40,43)),null,new Point(x+2,y+2),r*1.1,r*.3);dc.DrawGeometry(Frozen(Color.FromRgb(89,112,115)),Stroke(Color.FromArgb(110,208,221,215),.7),BlobGeometry(x,y,r,r*.57,seed,7));dc.DrawGeometry(Frozen(Color.FromRgb(165,189,187)),null,BlobGeometry(x-r*.2,y-r*.17,r*.54,r*.26,seed+4,6));dc.DrawLine(Stroke(Color.FromArgb(120,232,242,237),.8),new Point(x-r*.44,y-r*.1),new Point(x-r*.14,y-r*.34));return;}
            if(scene==1){dc.DrawEllipse(Frozen(Color.FromArgb(45,16,12,9)),null,new Point(x+2,y+2),r*1.05,r*.29);dc.DrawGeometry(Frozen(Color.FromRgb(66,53,41)),Stroke(Color.FromArgb(100,40,35,29),.6),BlobGeometry(x,y,r,r*.45,seed,8));Pen ash=Stroke(Color.FromArgb(105,161,104,69),.8);dc.DrawLine(ash,new Point(x-r*.4,y-r*.12),new Point(x-r*.03,y-r*.42));dc.DrawLine(ash,new Point(x+r*.08,y-r*.37),new Point(x+r*.43,y-r*.2));if(seed%5==0)dc.DrawLine(Stroke(Color.FromArgb(140,220,112,52),1.3),new Point(x+1,y-r*.16),new Point(x+4,y-r*.42));return;}
            Color dark=Color.FromRgb(31,69,43),light=Color.FromRgb(73,112,54);dc.DrawEllipse(Frozen(Color.FromArgb(48,12,18,13)),null,new Point(x+2,y+2),r*1.1,r*.28);dc.DrawGeometry(Frozen(dark),Stroke(Color.FromArgb(100,19,48,32),.7),BlobGeometry(x,y-r*.02,r*1.04,r*.57,seed,11));dc.DrawGeometry(Frozen(light),null,BlobGeometry(x-r*.12,y-r*.21,r*.68,r*.36,seed+4,8));for(int i=0;i<3;i++){double lx=x+(i-1)*r*.42,ly=y-r*.42-(i%2)*r*.1;DrawLeaf(dc,lx,ly,r*.64,r*.2,(i-1)*.48,Color.FromArgb(150,113,157,74));}if(seed%4==0)dc.DrawLine(Stroke(Color.FromArgb(170,188,194,111),1),new Point(x+r*.4,y-r*.24),new Point(x+r*.58,y-r*.48));
        }
        private void DrawReliefRock(DrawingContext dc,double x,double y,double r,int biome,int seed)
        {
            dc.DrawEllipse(Frozen(Color.FromArgb(62,18,22,18)),null,new Point(x+r*.13,y+r*.22),r*1.04,r*.35);
            Color baseColor=biome==0?Color.FromRgb((byte)(61+seed%4*4),(byte)(72+seed%3*5),60):biome==1?Color.FromRgb((byte)(75+seed%4*5),53,39):Color.FromRgb((byte)(96+seed%3*5),119,125);
            Color face=biome==0?Color.FromRgb(90,105,79):biome==1?Color.FromRgb(111,75,51):Color.FromRgb(146,163,164);
            Color light=biome==0?Color.FromRgb(133,144,104):biome==1?Color.FromRgb(150,99,62):Color.FromRgb(190,207,202);
            dc.DrawGeometry(Frozen(baseColor),Stroke(Color.FromArgb(105,30,36,31),1.1*MapScale),BlobGeometry(x,y,r,r*.68,seed,8));
            dc.DrawGeometry(Frozen(face),null,BlobGeometry(x-r*.18,y-r*.18,r*.66,r*.50,seed+7,7));
            Triangle(dc,Frozen(light),x-r*.38,y-r*.28,x-r*.08,y-r*.62,x+r*.08,y-r*.20);
            dc.DrawLine(Stroke(Color.FromArgb(115,235,226,187),Math.Max(.7,MapScale)),new Point(x-r*.31,y-r*.25),new Point(x-r*.08,y-r*.54));
            if(seed%3==0)dc.DrawLine(Stroke(Color.FromArgb(92,28,35,30),.9*MapScale),new Point(x+r*.08,y-r*.03),new Point(x+r*.28,y+r*.20));
        }
        private void DrawScenicProp(DrawingContext dc,double x,double y,double s,int biome,int seed)
        {
            dc.DrawEllipse(Frozen(Color.FromArgb(43,9,14,14)),null,new Point(x+s*.13,y+s*.20),s*1.35,s*.34);
            if(biome==0)
            {
                int kind=seed%4;if(kind==0){double a=(seed%7-3)*.11,dx=Math.Cos(a)*s,dy=Math.Sin(a)*s;dc.DrawLine(Stroke(Color.FromArgb(115,43,34,25),s*.46),new Point(x-dx,y-dy),new Point(x+dx,y+dy));dc.DrawLine(Stroke(Color.FromArgb(210,113,83,48),s*.29),new Point(x-dx*.82,y-dy*.82),new Point(x+dx*.78,y+dy*.78));for(int k=-1;k<=1;k+=2){double px=x+k*dx*.63,py=y+k*dy*.63;dc.DrawEllipse(Frozen(Color.FromRgb(93,68,43)),null,new Point(px,py),s*.15,s*.18);dc.DrawEllipse(Frozen(Color.FromRgb(151,112,69)),null,new Point(px-s*.04,py-s*.04),s*.07,s*.09);}dc.DrawLine(Stroke(Color.FromArgb(160,75,52,32),s*.11),new Point(x-s*.26,y-s*.08),new Point(x-s*.47,y-s*.48));}
                else if(kind==1){for(int j=0;j<7;j++){double a=-1.25+j*.42,len=s*(.55+(j%3)*.10),lx=x+Math.Cos(a)*len*.42,ly=y-Math.Sin(a)*len*.62;DrawLeaf(dc,lx,ly,len,s*.20,a,Color.FromRgb((byte)(55+j%3*11),(byte)(103+j%4*9),(byte)(52+j%2*8)));}dc.DrawLine(Stroke(Color.FromRgb(100,75,49),s*.10),new Point(x,y),new Point(x,y-s*.7));}
                else if(kind==2){dc.DrawLine(Stroke(Color.FromRgb(92,60,43),s*.14),new Point(x,y),new Point(x,y-s*.55));dc.DrawEllipse(Frozen(Color.FromRgb(209,194,153)),null,new Point(x,y-s*.56),s*.22,s*.13);dc.DrawEllipse(Frozen(Color.FromRgb(221,153,98)),null,new Point(x+s*.08,y-s*.58),s*.08,s*.11);}
                else{dc.DrawEllipse(Frozen(Color.FromRgb(79,65,43)),null,new Point(x,y-s*.20),s*.30,s*.38);dc.DrawEllipse(Frozen(Color.FromRgb(120,93,55)),null,new Point(x-s*.04,y-s*.43),s*.27,s*.11);for(int j=0;j<3;j++)dc.DrawLine(Stroke(Color.FromArgb(130,192,150,89),s*.035),new Point(x-s*.12+j*s*.1,y-s*.48),new Point(x-s*.1+j*s*.1,y-s*.08));}
            }
            else if(biome==1)
            {
                if(seed%3==0){dc.DrawLine(Stroke(Color.FromArgb(180,40,30,25),s*.20),new Point(x-s*.55,y+s*.08),new Point(x+s*.48,y-s*.20));dc.DrawLine(Stroke(Color.FromArgb(125,140,75,46),s*.075),new Point(x-s*.35,y),new Point(x+s*.20,y-s*.27));dc.DrawLine(Stroke(Color.FromArgb(140,241,108,46),s*.035),new Point(x+s*.14,y-s*.27),new Point(x+s*.34,y-s*.45));}
                else{DrawReliefRock(dc,x,y,s*.56,biome,seed);if(seed%3==1){dc.DrawLine(Stroke(Color.FromArgb(160,65,46,33),s*.12),new Point(x-s*.28,y+s*.12),new Point(x+s*.28,y-s*.18));dc.DrawLine(Stroke(Color.FromArgb(150,193,103,59),s*.045),new Point(x-s*.18,y+s*.06),new Point(x+s*.18,y-s*.17));}}
            }
            else
            {
                for(int j=0;j<3;j++){double ox=(j-1)*s*.30,h=s*(.68+(j%2)*.25);Triangle(dc,Frozen(Color.FromRgb((byte)(87+j*16),(byte)(133+j*13),(byte)(148+j*12))),x+ox,y-h,x+ox-s*.23,y,x+ox+s*.23,y);Triangle(dc,Frozen(Color.FromArgb(178,213,240,235)),x+ox,y-h,x+ox-s*.11,y-h*.35,x+ox+s*.02,y-h*.25);}
            }
        }
        private StreamGeometry BlobGeometry(double x,double y,double rx,double ry,int seed,int sides)
        {
            StreamGeometry g=new StreamGeometry();using(StreamGeometryContext c=g.Open()){for(int i=0;i<sides;i++){double a=2*Math.PI*i/sides,variation=.84+.12*Math.Sin(i*2.37+seed*.71)+.05*Math.Cos(i*3.91-seed);Point p=new Point(x+Math.Cos(a)*rx*variation,y+Math.Sin(a)*ry*variation);if(i==0)c.BeginFigure(p,true,true);else c.LineTo(p,true,false);}}g.Freeze();return g;
        }
        private void DrawLeaf(DrawingContext dc,double x,double y,double length,double width,double angle,Color color)
        {
            double cs=Math.Cos(angle),sn=Math.Sin(angle);Point[] p=new Point[4];double[] lx={-length*.5,0,length*.5,0},ly={0,-width*.5,0,width*.5};for(int i=0;i<4;i++)p[i]=new Point(x+lx[i]*cs-ly[i]*sn,y+lx[i]*sn+ly[i]*cs);StreamGeometry g=new StreamGeometry();using(StreamGeometryContext c=g.Open()){c.BeginFigure(p[0],true,true);c.LineTo(p[1],true,false);c.LineTo(p[2],true,false);c.LineTo(p[3],true,false);}g.Freeze();dc.DrawGeometry(Frozen(color),null,g);dc.DrawLine(Stroke(Color.FromArgb((byte)(color.A*.55),color.R,color.G,color.B),.65),p[0],p[2]);
        }
        private void DrawRoadStone(DrawingContext dc,double x,double y,double rx,double ry,int seed,Color fill)
        {
            dc.DrawGeometry(Frozen(fill),null,BlobGeometry(x,y,rx,ry,seed,5+seed%3));if(seed%3==0)dc.DrawLine(Stroke(Color.FromArgb(86,230,211,168),.7),new Point(x-rx*.38,y-ry*.18),new Point(x+rx*.17,y-ry*.39));
        }
        private void DrawRuin(DrawingContext dc,double x,double y,double h,int i){Brush b=Frozen(Color.FromRgb((byte)(72+i%3*4),(byte)(58+i%3*3),48));StreamGeometry g=new StreamGeometry();using(StreamGeometryContext c=g.Open()){c.BeginFigure(new Point(x-h*.5,y+h*.2),true,true);c.LineTo(new Point(x-h*.28,y-h*.4),true,false);c.LineTo(new Point(x+h*.26,y-h*.62),true,false);c.LineTo(new Point(x+h*.52,y+h*.2),true,false);}g.Freeze();dc.DrawGeometry(b,null,g);dc.DrawLine(new Pen(Frozen(Color.FromArgb(142,216,137,73)),1),new Point(x-4,y),new Point(x+1,y-9));}
        private void DrawIceRock(DrawingContext dc,double x,double y,double h,int i){Brush b=Frozen(Color.FromRgb((byte)(43+i%3*7),(byte)(77+i%3*7),(byte)(91+i%3*7)));Triangle(dc,b,x,y-h,x-h*.55,y+h*.25,x+h*.48,y+h*.25);dc.DrawLine(new Pen(Frozen(Color.FromArgb(145,214,242,247)),1),new Point(x,y-h),new Point(x-4,y-2));}
        private void DrawRoad(DrawingContext dc,int scene,Random random)
        {
            if(routeGeometry==null)return;Color edge=scene==0?Color.FromRgb(47,39,29):scene==1?Color.FromRgb(43,32,24):Color.FromRgb(55,67,67),soil=scene==0?Color.FromRgb(119,100,70):scene==1?Color.FromRgb(104,73,49):Color.FromRgb(130,129,111),sun=scene==0?Color.FromRgb(158,137,96):scene==1?Color.FromRgb(145,99,58):Color.FromRgb(166,163,140);
            dc.DrawGeometry(null,new Pen(Frozen(edge),72*MapScale){LineJoin=PenLineJoin.Round,StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round},routeGeometry);dc.DrawGeometry(null,new Pen(Frozen(soil),61*MapScale){LineJoin=PenLineJoin.Round,StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round},routeGeometry);dc.DrawGeometry(null,new Pen(Frozen(sun),51*MapScale){LineJoin=PenLineJoin.Round,StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round},routeGeometry);dc.DrawGeometry(null,new Pen(Frozen(Color.FromRgb(177,157,116)),43*MapScale){LineJoin=PenLineJoin.Round,StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round},routeGeometry);
            for(int i=1;i<motionPath.Length;i++){Point a=motionPath[i-1],b=motionPath[i];double dx=b.X-a.X,dy=b.Y-a.Y,len=Math.Sqrt(dx*dx+dy*dy);if(len<.1)continue;int n=Math.Max(1,(int)(len/(17*MapScale)));for(int k=0;k<n;k++){double u=(k+random.NextDouble()*.8)/n,cx=a.X+dx*u,cy=a.Y+dy*u,nx=-dy/len,ny=dx/len,side=(random.NextDouble()-.5)*34*MapScale,px=cx+nx*side,py=cy+ny*side,size=(1.4+random.NextDouble()*3.3)*MapScale;Color stone=scene==0?(random.Next(3)==0?Color.FromArgb(91,97,74,51):Color.FromArgb(79,207,183,133)):scene==1?(random.Next(3)==0?Color.FromArgb(91,68,47,35):Color.FromArgb(88,187,123,74)):Color.FromArgb(102,225,218,190);DrawRoadStone(dc,px,py,size,size*.42,k+i,stone);if(k%4==0){Pen rut=Stroke(Color.FromArgb(43,45,34,24),.8*MapScale);dc.DrawLine(rut,new Point(px-nx*size*2,py-ny*size*2),new Point(px+nx*size*2,py+ny*size*2));}}}
            for(int i=0;i<motionPath.Length;i+=3){Point p=motionPath[i],q=motionPath[Math.Min(i+1,motionPath.Length-1)];double dx=q.X-p.X,dy=q.Y-p.Y,len=Math.Sqrt(dx*dx+dy*dy);if(len<.1)continue;double nx=-dy/len,ny=dx/len;for(int side=-1;side<=1;side+=2){if(random.NextDouble()>.56)continue;double x=p.X+nx*side*37*MapScale,y=p.Y+ny*side*37*MapScale;Pen grass=Stroke(scene==0?Color.FromArgb(145,163,174,100):scene==1?Color.FromArgb(155,190,119,68):Color.FromArgb(175,225,240,235),1.2*MapScale);dc.DrawLine(grass,new Point(x,y),new Point(x+nx*side*3*MapScale+dy/len*random.Next(-4,5)*MapScale,y+ny*side*3*MapScale-dx/len*random.Next(-4,5)*MapScale));}}
            dc.DrawGeometry(null,new Pen(Frozen(Color.FromArgb(72,245,223,174)),1.6*MapScale){DashStyle=new DashStyle(new[]{3.0*MapScale,12.0*MapScale},1)},routeGeometry);
        }
        private void DrawGates(DrawingContext dc,int scene)
        {
            double g=MapScale;Point start=path[0],end=path[path.Length-1];DrawGate(dc,start.X,start.Y,g,true,scene,start.X<WorldW*.5);DrawGate(dc,end.X,end.Y,g,false,scene,end.X<WorldW*.5);
        }
        private void DrawGate(DrawingContext dc,double x,double y,double g,bool entrance,int scene,bool left)
        {
            double w=94*g,h=94*g;StreamGeometry cliff=new StreamGeometry();using(StreamGeometryContext c=cliff.Open()){c.BeginFigure(new Point(x-w*.51,y+h*.26),true,true);c.LineTo(new Point(x-w*.49,y-h*.23),true,false);c.BezierTo(new Point(x-w*.48,y-h*.72),new Point(x-w*.21,y-h*.94),new Point(x,y-h*.91),true,false);c.BezierTo(new Point(x+w*.27,y-h*.94),new Point(x+w*.49,y-h*.67),new Point(x+w*.49,y-h*.20),true,false);c.LineTo(new Point(x+w*.51,y+h*.26),true,false);}cliff.Freeze();LinearGradientBrush stone=new LinearGradientBrush(scene==1?Color.FromRgb(83,64,49):Color.FromRgb(99,105,99),scene==2?Color.FromRgb(41,72,86):Color.FromRgb(44,47,43),-40);stone.Freeze();dc.DrawEllipse(Frozen(Color.FromArgb(72,11,13,13)),null,new Point(x,y+h*.20),w*.65,h*.19);dc.DrawGeometry(Frozen(Color.FromRgb(32,30,27)),Stroke(Color.FromArgb(175,38,32,27),2*g),cliff);StreamGeometry mouth=new StreamGeometry();using(StreamGeometryContext c=mouth.Open()){c.BeginFigure(new Point(x-w*.30,y+h*.24),true,true);c.LineTo(new Point(x-w*.30,y-h*.18),true,false);c.BezierTo(new Point(x-w*.28,y-h*.53),new Point(x-w*.14,y-h*.66),new Point(x,y-h*.64),true,false);c.BezierTo(new Point(x+w*.18,y-h*.66),new Point(x+w*.30,y-h*.46),new Point(x+w*.30,y-h*.16),true,false);c.LineTo(new Point(x+w*.30,y+h*.24),true,false);}mouth.Freeze();dc.DrawGeometry(stone,Stroke(Color.FromArgb(170,177,153,111),1.5*g),cliff);dc.DrawGeometry(Frozen(Color.FromRgb(7,10,12)),Stroke(Color.FromArgb(190,26,29,29),1*g),mouth);
            Color glow=entrance?scene==1?Color.FromRgb(255,123,49):scene==2?Color.FromRgb(147,225,250):Color.FromRgb(225,175,82):scene==2?Color.FromRgb(104,194,225):Color.FromRgb(207,128,59);dc.DrawEllipse(Frozen(Color.FromArgb(32,glow.R,glow.G,glow.B)),null,new Point(x,y+h*.12),w*.22,h*.10);dc.DrawLine(Stroke(Color.FromArgb(105,glow.R,glow.G,glow.B),1.5*g),new Point(x-w*.17,y+h*.18),new Point(x+w*.17,y+h*.18));
            for(int side=-1;side<=1;side+=2){double px=x+side*w*.39;dc.DrawEllipse(Frozen(Color.FromRgb(47,46,41)),Stroke(Color.FromArgb(145,133,122,92),.9*g),new Point(px,y-h*.55),w*.16,h*.16);dc.DrawEllipse(Frozen(Color.FromRgb(90,92,81)),null,new Point(px-side*w*.025,y-h*.60),w*.085,h*.06);dc.DrawEllipse(Frozen(Color.FromRgb(48,46,41)),Stroke(Color.FromArgb(125,125,118,93),.7*g),new Point(x+side*w*.47,y+h*.14),w*.12,h*.09);dc.DrawLine(Stroke(Color.FromArgb(110,208,183,124),.9*g),new Point(x+side*w*.42,y-h*.43),new Point(x+side*w*.32,y-h*.13));}
            if(!entrance)return;string[] names={"ЧЁРНЫЕ ВРАТА","ПЕПЕЛЬНЫЙ ПРОХОД","СЕВЕРНЫЙ ПРОХОД","ИТИЛИЭН","МОРОЗНЫЕ КОПИ","РОХАН","ЗОЛОТОЙ ЛЕС","ЭРЕБОР","ЧЁРНЫЕ ЗЕМЛИ","МИНАС-ТИРИТ","ТУМАННЫЕ ГОРЫ","ЗАПАДНЫЙ КРАЙ","ДОЛ ГУЛДУР","АНГМАР","КХАЗАД-ДУМ","ЛИХОЛЕСЬЕ","ПЕЛЕННОР","УДУН"};string mapName=names[Math.Min(arenaIndex,names.Length-1)];double tx=left?Math.Max(4*g,x+52*g):Math.Min(WorldW-200*g,x-190*g);dc.DrawText(new FormattedText(mapName,System.Globalization.CultureInfo.GetCultureInfo("ru-RU"),FlowDirection.LeftToRight,new Typeface("Georgia"),13*g,Frozen(Color.FromRgb(241,213,151)),1.0),new Point(tx,y-h*1.05));
        }
        private static void Triangle(DrawingContext dc,Brush brush,double x1,double y1,double x2,double y2,double x3,double y3){StreamGeometry g=new StreamGeometry();using(StreamGeometryContext c=g.Open()){c.BeginFigure(new Point(x1,y1),true,true);c.LineTo(new Point(x2,y2),true,false);c.LineTo(new Point(x3,y3),true,false);}g.Freeze();dc.DrawGeometry(brush,null,g);}
        private void DrawTower(DrawingContext dc,Tower t)
        {
            double g=MapScale,y=MapScreenY(t.X,t.Y);if(t==selectedTower)dc.DrawEllipse(null,Stroke(Color.FromArgb(120,247,219,144),1.8*g),new Point(t.X,y),t.Range,t.Range);
            if(t.Type.Id=="aura"){Color aura=t.Aura=="damage"?Color.FromArgb(43,245,175,67):Color.FromArgb(43,116,217,138);dc.DrawEllipse(null,Stroke(aura,5*g),new Point(t.X,y),t.Range,t.Range);}
            dc.DrawEllipse(Frozen(Color.FromArgb(86,8,11,10)),null,new Point(t.X,y+5*g),28*g,8*g);dc.DrawEllipse(Frozen(Color.FromRgb(41,45,43)),Stroke(Color.FromRgb(77,72,57),1*g),new Point(t.X,y+1*g),25*g,9*g);dc.DrawEllipse(Frozen(Color.FromRgb(121,104,72)),Stroke(Color.FromRgb(226,201,139),1.25*g),new Point(t.X,y-2*g),22*g,8*g);dc.DrawEllipse(Frozen(Color.FromRgb(61,55,43)),Stroke(Color.FromArgb(190,239,216,160),.7*g),new Point(t.X,y-2*g),18*g,5.5*g);
            dc.DrawRoundedRectangle(Frozen(Color.FromArgb(237,16,20,20)),Stroke(Color.FromArgb(190,212,183,123),.65*g),new Rect(t.X-12*g,y+5*g,24*g,11*g),3*g,3*g);DrawText(dc,"L"+(t.Level+1),t.X-8*g,y+5.4*g,8.5*g,Frozen(Color.FromRgb(248,227,178)),true);
        }
        private double AttackPose(double age)
        {
            if(age<0||age>=.46)return 0;
            if(age<.10)return -.30*Math.Sin(age/.10*Math.PI*.5);
            if(age<.19){double p=(age-.10)/.09;p=p*p*(3-2*p);return -.30+1.30*p;}
            if(age<.29){double p=(age-.19)/.10;p=p*p*(3-2*p);return 1-.28*p;}
            double q=(age-.29)/.17;q=q*q*(3-2*q);return .72*(1-q);
        }
        private static readonly Dictionary<Color,Brush> glowCache=new Dictionary<Color,Brush>();
        private Brush UpgradeGlow(Color color,int level)
        {
            byte strength=(byte)(17+level*9);Color key=Color.FromArgb(strength,color.R,color.G,color.B);Brush brush;if(glowCache.TryGetValue(key,out brush))return brush;RadialGradientBrush radial=new RadialGradientBrush();radial.GradientOrigin=new Point(.5,.45);radial.Center=new Point(.5,.45);radial.GradientStops.Add(new GradientStop(Color.FromArgb(strength,color.R,color.G,color.B),0));radial.GradientStops.Add(new GradientStop(Color.FromArgb((byte)(strength/3),color.R,color.G,color.B),.58));radial.GradientStops.Add(new GradientStop(Color.FromArgb(0,color.R,color.G,color.B),1));radial.Freeze();glowCache[key]=radial;return radial;
        }
        private void DrawUpgradeGlow(DrawingContext dc,Tower t,Color c)
        {
            if(t.Level<=0)return;double scale=MapScale*(1+t.Level*.08);dc.DrawEllipse(UpgradeGlow(c,t.Level),null,new Point(t.X,t.Y-34*scale),27*scale,39*scale);
        }
        private void DrawUpgradeMantle(DrawingContext dc,Tower t,Color c)
        {
            if(t.Level<=0)return;double g=MapScale;byte alpha=(byte)(72+t.Level*24);Pen energy=Stroke(Color.FromArgb(alpha,c.R,c.G,c.B),(1.0+t.Level*.38)*g);for(int side=-1;side<=1;side+=2){Point a=new Point(t.X+side*22*g,t.Y-5*g),b=new Point(t.X+side*18*g,t.Y-25*g),d=new Point(t.X+side*15*g,t.Y-45*g),e=new Point(t.X+side*8*g,t.Y-66*g);dc.DrawLine(energy,a,b);dc.DrawLine(energy,b,d);dc.DrawLine(energy,d,e);if(t.Level>=3){Pen glint=Stroke(Color.FromArgb((byte)(alpha*.55),239,230,201),.8*g);dc.DrawLine(glint,new Point(a.X-side*2*g,a.Y),new Point(b.X-side*1*g,b.Y));}}
            if(t.Level>=4)DrawSignatureMantle(dc,t,c);
        }
        private void DrawSignatureMantle(DrawingContext dc,Tower t,Color c)
        {
            double g=MapScale;byte alpha=(byte)(130+35*Math.Sin(clock*3+t.X*.01));Pen p=Stroke(Color.FromArgb(alpha,c.R,c.G,c.B),2.0*g);double pulse=Math.Sin(clock*2.8+t.X*.02)*2*g;
            if(t.Type.Id=="gondor"){dc.DrawLine(p,new Point(t.X-23*g,t.Y-23*g),new Point(t.X+4*g,t.Y-54*g+pulse));dc.DrawLine(p,new Point(t.X-20*g,t.Y-18*g),new Point(t.X+8*g,t.Y-49*g+pulse));}
            else if(t.Type.Id=="elf"){dc.DrawLine(p,new Point(t.X-26*g,t.Y-43*g),new Point(t.X-7*g,t.Y-58*g+pulse));dc.DrawLine(p,new Point(t.X+26*g,t.Y-39*g),new Point(t.X+8*g,t.Y-59*g-pulse));}
            else if(t.Type.Id=="dwarf"){dc.DrawLine(p,new Point(t.X-16*g,t.Y-44*g),new Point(t.X-23*g,t.Y-57*g-pulse));dc.DrawLine(p,new Point(t.X-23*g,t.Y-57*g-pulse),new Point(t.X-14*g,t.Y-68*g));dc.DrawLine(p,new Point(t.X+14*g,t.Y-43*g),new Point(t.X+21*g,t.Y-58*g+pulse));}
            else if(t.Type.Id=="aura"){dc.DrawLine(p,new Point(t.X-20*g,t.Y-54*g),new Point(t.X+18*g,t.Y-26*g+pulse));dc.DrawLine(p,new Point(t.X+20*g,t.Y-54*g),new Point(t.X-17*g,t.Y-27*g-pulse));}
            else{dc.DrawLine(p,new Point(t.X-24*g,t.Y-34*g),new Point(t.X-10*g,t.Y-54*g+pulse));dc.DrawLine(p,new Point(t.X-10*g,t.Y-54*g+pulse),new Point(t.X+11*g,t.Y-62*g));dc.DrawLine(p,new Point(t.X+11*g,t.Y-62*g),new Point(t.X+24*g,t.Y-40*g));}
        }
        private void DrawShotMotion(DrawingContext dc,Tower t,double attack,Color c)
        {
            double g=MapScale,aimX=Math.Sign(t.LastTargetX-t.X);Point from=new Point(t.X+aimX*18*g,t.Y-68*g),aim=new Point(t.LastTargetX,t.LastTargetY-25*g);double dx=aim.X-from.X,dy=aim.Y-from.Y,length=Math.Sqrt(dx*dx+dy*dy);if(length<.1){dx=aimX;dy=0;length=1;}double ux=dx/length,uy=dy/length,nx=-uy,ny=ux,reach=(10+47*attack)*g;Point tip=new Point(from.X+ux*reach,from.Y+uy*reach),tail=new Point(from.X-ux*5*g,from.Y-uy*5*g);byte alpha=(byte)(80+165*attack);Pen outer=Stroke(Color.FromArgb((byte)(alpha*.38),c.R,c.G,c.B),(3+7*attack)*g);dc.DrawLine(outer,tail,tip);Pen core=Stroke(Color.FromArgb(alpha,255,246,220),(1.2+2.2*attack)*g);dc.DrawLine(core,new Point(from.X+nx*2*g,from.Y+ny*2*g),new Point(tip.X+nx*3*g,tip.Y+ny*3*g));if(t.Type.Id=="gondor"){dc.DrawLine(Stroke(Color.FromArgb(alpha,c.R,c.G,c.B),3.2*g),new Point(from.X-nx*5*g,from.Y-ny*5*g),new Point(tip.X-nx*2*g,tip.Y-ny*2*g));}else if(t.Type.Id=="elf"||t.Type.Id=="ice"){DrawMagicRibbon(dc,tail,tip,nx,ny,5*g,c,1.8*g,clock*13);}else if(t.Type.Id=="dwarf"){dc.DrawLine(Stroke(Color.FromArgb((byte)(alpha*.8),255,145,58),4*attack*g),tail,new Point(tip.X-ux*8*g,tip.Y-uy*8*g));}
        }
        private void DrawAttackGesture(DrawingContext dc,Tower t,double pose,double attack,Color c,double aim)
        {
            double g=MapScale;Point shoulder=new Point(t.X+aim*5*g,t.Y-70*g),elbow=new Point(t.X+aim*(12-9*Math.Max(0,-pose)+16*Math.Max(0,pose))*g,t.Y-60*g+pose*3*g),hand=new Point(t.X+aim*(20-18*Math.Max(0,-pose)+36*Math.Max(0,pose))*g,t.Y-52*g-pose*5*g);byte alpha=(byte)(85+160*attack);Pen sleeve=Stroke(Color.FromArgb(alpha,c.R,c.G,c.B),(5.2+1.2*attack)*g),skin=Stroke(Color.FromArgb(alpha,239,222,194),(3.6+1.1*attack)*g);dc.DrawLine(sleeve,shoulder,elbow);dc.DrawLine(skin,elbow,hand);dc.DrawEllipse(Frozen(Color.FromArgb((byte)(80+140*attack),c.R,c.G,c.B)),null,hand,(3+2.6*attack)*g,(3+2.6*attack)*g);
            if(t.Type.Id=="gondor")
            {
                Point blade=new Point(hand.X+aim*19*g,hand.Y-17*g);dc.DrawLine(Stroke(Color.FromArgb((byte)(70+150*attack),28,23,36),6*g),hand,blade);dc.DrawLine(Stroke(Color.FromArgb(alpha,199,211,213),2*g),new Point(hand.X+aim*3*g,hand.Y-3*g),blade);dc.DrawLine(Stroke(Color.FromArgb((byte)(alpha*.72),c.R,c.G,c.B),3.2*g),new Point(hand.X-aim*12*g,hand.Y-12*g),new Point(hand.X+aim*18*g,hand.Y-27*g));
            }
            else if(t.Type.Id=="elf")DrawMagicRibbon(dc,new Point(hand.X-aim*13*g,hand.Y+8*g),new Point(hand.X+aim*18*g,hand.Y-15*g),-aim*.35,-1,9*g,Color.FromArgb((byte)(alpha*.8),215,250,233),2.4*g,clock*11);
            else if(t.Type.Id=="dwarf"){for(int i=0;i<3;i++){double a=clock*9+i*2.1;Point spark=new Point(hand.X+Math.Cos(a)*7*g,hand.Y+Math.Sin(a)*7*g);dc.DrawLine(Stroke(Color.FromArgb((byte)(alpha*.8),255,174,68),2.2*g),hand,spark);}}
            else if(t.Type.Id=="aura")DrawMagicRibbon(dc,new Point(hand.X-aim*12*g,hand.Y-9*g),new Point(hand.X+aim*24*g,hand.Y-24*g),0,-1,12*g,Color.FromArgb((byte)(alpha*.72),235,97,149),2.1*g,clock*9);
            else{Point spear=new Point(hand.X+aim*22*g,hand.Y-19*g);dc.DrawLine(Stroke(Color.FromArgb((byte)(alpha*.85),132,223,250),4*g),hand,spear);dc.DrawLine(Stroke(Color.FromArgb(alpha,242,255,255),1.5*g),hand,spear);}
        }
        private void DrawEnemyIndicators(DrawingContext dc)
        {
            foreach(Enemy e in enemies){double g=MapScale,h=e.Kind=="goblin"?90:e.Kind=="orc"?118:e.Kind=="uruk"?132:e.Kind=="warg"?82:e.Kind=="troll"?220:e.Kind=="nazgul"?158:110;if(e.Boss)h*=1.18;h*=1.10;double footY=MapScreenY(e.X,e.Y)-2.8*g,width=Math.Max(38*g,h*.54),barY=footY-h-8*g,fraction=Math.Max(0,Math.Min(1,e.Hp/Math.Max(1,e.MaxHp)));dc.DrawRoundedRectangle(Frozen(Color.FromArgb(235,18,21,20)),Stroke(Color.FromArgb(150,213,194,147),.7*g),new Rect(e.X-width/2,barY,width,5*g),2*g,2*g);dc.DrawRoundedRectangle(Frozen(fraction>.45?Color.FromRgb(116,207,102):Color.FromRgb(220,76,60)),null,new Rect(e.X-width/2+1*g,barY+1*g,(width-2*g)*fraction,3*g),1.4*g,1.4*g);if(e.SlowUntil>clock){double phase=clock*5+e.Phase;for(int i=0;i<2;i++){double x=e.X+(i==0?-1:1)*h*.25+Math.Sin(phase+i)*3*g,y=footY-h*.50+Math.Cos(phase+i)*5*g;dc.DrawEllipse(Frozen(Color.FromArgb(95,151,231,255)),null,new Point(x,y),5*g,5*g);dc.DrawLine(Stroke(Color.FromArgb(220,220,250,255),1.3*g),new Point(x-2*g,y-3*g),new Point(x+2*g,y+3*g));}}
            }
        }
        private static Rect FitRect(BitmapSource image,double cx,double bottom,double height,double maxWidth){double ar=(double)image.PixelWidth/image.PixelHeight;double h=Math.Min(height,maxWidth/ar);double w=h*ar;return new Rect(cx-w/2,bottom-h,w,h);}
        private void DrawBolt(DrawingContext dc,Bolt b)
        {
            double g=MapScale,phase=clock*9+b.Phase;Color c=TypeColor(b.Type,b.Source.Level);Point core=new Point(b.X,b.Y-15*g),target=b.Target==null?new Point(core.X+1,core.Y):new Point(b.Target.X,b.Target.Y-37*g);double dx=target.X-core.X,dy=target.Y-core.Y,length=Math.Sqrt(dx*dx+dy*dy);if(length<.1){dx=1;dy=0;length=1;}double ux=dx/length,uy=dy/length,nx=-uy,ny=ux;Point tail=new Point(core.X-ux*40*g,core.Y-uy*40*g),tip=new Point(core.X+ux*10*g,core.Y+uy*10*g);byte alpha=(byte)(205+50*(.5+.5*Math.Sin(phase)));
            if(b.Type=="elf"){DrawMagicRibbon(dc,tail,tip,nx,ny,12*g,Color.FromArgb(95,116,245,194),5*g,phase);DrawMagicRibbon(dc,tail,tip,-nx,-ny,8*g,Color.FromArgb(175,226,255,238),2.7*g,phase+1.7);DrawMagicRibbon(dc,new Point(tail.X-ux*8*g,tail.Y-uy*8*g),tip,nx,ny,4*g,Color.FromArgb(220,255,255,249),1.2*g,phase+3.3);for(int i=0;i<3;i++){double a=phase+i*2.094;Point p=new Point(core.X-ux*(14+i*10)*g+nx*Math.Sin(a)*5*g,core.Y-uy*(14+i*10)*g+ny*Math.Sin(a)*5*g);dc.DrawEllipse(Frozen(Color.FromArgb(155,210,255,235)),null,p,1.8*g,1.8*g);}}
            else if(b.Type=="gondor"){dc.DrawLine(Stroke(Color.FromArgb(48,104,30,45),17*g),tail,tip);DrawMagicRibbon(dc,tail,tip,nx,ny,8*g,Color.FromArgb(140,109,26,48),4.2*g,phase);DrawMagicRibbon(dc,tail,tip,-nx,-ny,5*g,Color.FromArgb(220,165,51,62),2*g,phase+2.1);Triangle(dc,Frozen(Color.FromArgb(180,77,44,56)),core.X-ux*3*g,core.Y-uy*3*g,tail.X+nx*5*g,tail.Y+ny*5*g,tail.X-nx*5*g,tail.Y-ny*5*g);dc.DrawLine(Stroke(Color.FromArgb(alpha,236,86,91),1.2*g),new Point(core.X-ux*9*g+nx*1.5*g,core.Y-uy*9*g+ny*1.5*g),tip);}
            else if(b.Type=="ice"){dc.DrawLine(Stroke(Color.FromArgb(42,80,198,242),12*g),tail,tip);DrawMagicRibbon(dc,tail,tip,nx,ny,6*g,Color.FromArgb(155,102,219,255),2.8*g,phase);DrawMagicRibbon(dc,tail,tip,-nx,-ny,4*g,Color.FromArgb(205,225,252,255),1.3*g,phase+2.4);for(int i=0;i<3;i++){double s=i-1,travel=(9+i*8)*g;Point a=new Point(core.X-ux*travel+nx*s*5*g,core.Y-uy*travel+ny*s*5*g),d=new Point(a.X-ux*6*g+nx*s*4*g,a.Y-uy*6*g+ny*s*4*g);Triangle(dc,Frozen(Color.FromArgb((byte)(i==1?225:160),190,243,255)),a.X+ux*4*g,a.Y+uy*4*g,d.X+nx*2*g,d.Y+ny*2*g,d.X-nx*2*g,d.Y-ny*2*g);}}
            else{dc.DrawLine(Stroke(Color.FromArgb(45,255,66,20),20*g),tail,tip);DrawMagicRibbon(dc,tail,tip,nx,ny,12*g,Color.FromArgb(160,245,70,27),5.4*g,phase);DrawMagicRibbon(dc,tail,tip,-nx,-ny,9*g,Color.FromArgb(220,255,137,45),3.1*g,phase+1.8);DrawMagicRibbon(dc,tail,tip,nx,ny,4*g,Color.FromArgb(230,255,220,106),1.5*g,phase+3.1);for(int i=0;i<4;i++){double a=phase+i*1.57;Point p=new Point(core.X-ux*(12+i*6)*g+nx*Math.Sin(a)*4*g,core.Y-uy*(12+i*6)*g+ny*Math.Sin(a)*4*g);dc.DrawEllipse(Frozen(Color.FromArgb(175,255,166,53)),null,p,2*g,1.5*g);}}
        }
        private void DrawMagicRibbon(DrawingContext dc,Point start,Point end,double nx,double ny,double amplitude,Color color,double width,double phase)
        {
            double wave=Math.Sin(phase)*amplitude;Point c1=new Point(start.X+(end.X-start.X)*.32+nx*wave,start.Y+(end.Y-start.Y)*.32+ny*wave),c2=new Point(start.X+(end.X-start.X)*.68-nx*wave,start.Y+(end.Y-start.Y)*.68-ny*wave);StreamGeometry g=new StreamGeometry();using(StreamGeometryContext c=g.Open()){c.BeginFigure(start,false,false);c.BezierTo(c1,c2,end,true,false);}g.Freeze();dc.DrawGeometry(null,Stroke(color,width),g);
        }
        private void DrawBurst(DrawingContext dc,Burst b){double g=MapScale,q=b.Life/b.Duration,r=(6+q*27)*g;dc.DrawEllipse(null,Stroke(Color.FromArgb((byte)Math.Max(0,190*(1-q)),b.Color.R,b.Color.G,b.Color.B),2.4*g),new Point(b.X,b.Y),r,r);for(int i=0;i<5;i++){double a=i*1.256+clock*3;dc.DrawEllipse(Frozen(Color.FromArgb((byte)Math.Max(0,170*(1-q)),b.Color.R,b.Color.G,b.Color.B)),null,new Point(b.X+Math.Cos(a)*r,b.Y+Math.Sin(a)*r),2.5*g,2.5*g);}}
        private double MapScreenY(double x,double y){return y-TerrainHeight(x,y)*.848;}
        private void DrawPreview(DrawingContext dc,double x,double y){double g=MapScale;bool valid=ValidSpot(x,y);y=MapScreenY(x,y);Color c=valid?Color.FromArgb(80,111,207,122):Color.FromArgb(85,225,78,68);dc.DrawEllipse(Frozen(c),null,new Point(x,y),28*g,10*g);dc.DrawEllipse(null,Stroke(valid?Color.FromArgb(230,143,238,125):Color.FromArgb(235,246,105,93),2*g),new Point(x,y),35*g,20*g);HeroType t=selectedType;if(t!=null){dc.DrawEllipse(null,Stroke(Color.FromArgb(38,239,212,149),1.4*g),new Point(x,y-35*g),t.Range*g,t.Range*g);if(!valid)dc.DrawLine(Stroke(Color.FromArgb(230,244,111,94),2*g),new Point(x-18*g,y-18*g),new Point(x+18*g,y+18*g));}}
        private void DrawGameOverlay(DrawingContext dc,string title,string body){dc.DrawRectangle(Frozen(Color.FromArgb(88,8,12,12)),null,new Rect(0,0,WorldW,WorldH));Rect r=new Rect((WorldW-430)/2,(WorldH-218)/2,430,218);dc.DrawRoundedRectangle(Brushed(248,39,40,38,14,21,27),new Pen(Frozen(Color.FromRgb(198,158,87)),3),r,8,8);DrawText(dc,title,r.X+24,r.Y+39,30,gold,true);DrawText(dc,body,r.X+40,r.Y+90,14,ivory,false);}
        private static void DrawText(DrawingContext dc,string text,double x,double y,double size,Brush brush,bool bold){FormattedText f=new FormattedText(text,System.Globalization.CultureInfo.GetCultureInfo("ru-RU"),FlowDirection.LeftToRight,new Typeface(new FontFamily("Segoe UI"),FontStyles.Normal,bold?FontWeights.Bold:FontWeights.Normal,FontStretches.Normal),size,brush,1.0);dc.DrawText(f,new Point(x,y));}
    }
}
