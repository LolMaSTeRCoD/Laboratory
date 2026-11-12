using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace CadyTowerDefense
{
    internal static class Program
    {
        [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();
        [STAThread] private static void Main()
        {
            SetProcessDPIAware();
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }
    internal sealed class SmoothPanel : Panel
    {
        public SmoothPanel() { DoubleBuffered=true; ResizeRedraw=true; }
    }
    internal sealed class WarcraftPanel : Panel
    {
        public WarcraftPanel(){DoubleBuffered=true;BackColor=Color.FromArgb(22,29,36);Padding=new Padding(12);}
        protected override void OnPaintBackground(PaintEventArgs e)
        {
            Rectangle r=ClientRectangle;if(r.Width<2||r.Height<2)return;
            using(LinearGradientBrush b=new LinearGradientBrush(r,Color.FromArgb(39,43,45),Color.FromArgb(17,24,31),90f))e.Graphics.FillRectangle(b,r);
            using(Pen p=new Pen(Color.FromArgb(34,190,160,101),1))for(int y=8;y<r.Height;y+=32)e.Graphics.DrawLine(p,8,y,r.Width-8,y);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);Rectangle r=ClientRectangle;if(r.Width<8||r.Height<8)return;
            using(Pen outer=new Pen(Color.FromArgb(191,151,105,57),3))e.Graphics.DrawRectangle(outer,1,1,r.Width-3,r.Height-3);
            using(Pen inner=new Pen(Color.FromArgb(118,225,193,126),1))e.Graphics.DrawRectangle(inner,6,6,r.Width-13,r.Height-13);
            using(SolidBrush gold=new SolidBrush(Color.FromArgb(218,191,145,83)))for(int x=12;x<r.Width-12;x+=20){e.Graphics.FillRectangle(gold,x,3,5,2);e.Graphics.FillRectangle(gold,x,r.Height-5,5,2);}
        }
    }
    internal sealed class HeroType
    {
        public string Id,Name,Icon,Description,Special,Sprite;
        public int Price,Damage;
        public float Range,Rate;
        public int[] UpgradeCosts;
        public string[] Forms;
        public Color[] Colors;
    }
    internal sealed class Tower
    {
        public HeroType Type;
        public float X,Y,Range,Damage,Rate,Cooldown,Power=.30f,LastShot=-20;
        public int Level,Invested;
        public string Aura="speed";
    }
    internal sealed class Enemy
    {
        public string Kind,Name;
        public float Distance,X,Y,Speed,Hp,MaxHp,Radius,Slow=1,SlowUntil,Phase;
        public int Reward,PathSegment;
        public bool Boss;
    }
    internal sealed class Bolt
    {
        public Tower Source;
        public Enemy Target;
        public float X,Y,Damage,Speed,Slow=1,SlowTime,Splash,Freeze;
        public string Type;
        public HashSet<Enemy> Hit=new HashSet<Enemy>();
        public int Pierce;
    }
    internal sealed class Burst
    {
        public float X,Y,Life,Duration;
        public Color Color;
    }

    internal sealed class MainForm : Form
    {
        private const float WorldW=1200f,WorldH=700f;
        private readonly string root=AppDomain.CurrentDomain.BaseDirectory;
        private readonly Dictionary<string,Bitmap> heroes=new Dictionary<string,Bitmap>();
        private readonly Dictionary<string,Bitmap> foes=new Dictionary<string,Bitmap>();
        private readonly Bitmap[] sceneCache=new Bitmap[3];
        private PointF[] motionPath=new PointF[0];
        private float[] motionDistances=new float[0];
        private float routeLength;
        private readonly List<HeroType> types=new List<HeroType>();
        private readonly List<Tower> towers=new List<Tower>();
        private readonly List<Enemy> enemies=new List<Enemy>();
        private readonly List<Bolt> bolts=new List<Bolt>();
        private readonly List<Burst> bursts=new List<Burst>();
        private readonly SmoothPanel field=new SmoothPanel();
        private readonly Timer timer=new Timer();
        private readonly Stopwatch frameClock=Stopwatch.StartNew();
        private readonly Font towerBadgeFont=new Font("Segoe UI",7.4f,FontStyle.Bold);
        private readonly Label goldLabel=new Label(),waveLabel=new Label(),livesLabel=new Label(),arenaLabel=new Label();
        private readonly Label statusLabel=new Label();
        private Label selectedLabel,overlayTitle,overlayText,musicValue,effectValue;
        private Button startButton,pauseButton,musicButton,fullscreenButton,upgradeButton,sellButton,auraSpeedButton,auraDamageButton;
        private ComboBox speedSelector;
        private TrackBar musicVolume,effectVolume;
        private FlowLayoutPanel cardList;
        private Panel overlayPanel,pausePanel;
        private readonly MciAudio audio;
        private PointF mouseWorld=new PointF(-100,-100);
        private HeroType selectedType;
        private Tower selectedTower;
        private PointF[] path;
        private int arenaIndex,waveInArena,totalWaves,gold=360,lives=15,remainingSpawns;
        private bool waveRunning,stageReady,gameOver,musicOn,paused;
        private float spawnCountdown,clock,scale=1,offsetX,offsetY,gameSpeed=1f;
        private readonly string[] arenaShort={"Лес","Пепел","Север"};
        private readonly string[] enemyNames={"Гоблин-разведчик","Орк Мордора","Урук-хай","Всадник на варге","Боевой тролль","Назгул"};
        private readonly string[] enemyIds={"goblin","orc","uruk","warg","troll","nazgul"};
        private readonly Color goldColor=Color.FromArgb(236,202,112),ink=Color.FromArgb(236,232,215),muted=Color.FromArgb(163,174,158);

        [DllImport("winmm.dll",CharSet=CharSet.Auto)] private static extern int mciSendString(string command,StringBuilder result,int length,IntPtr callback);

        public MainForm()
        {
            Text="Кади · Рубеж Средиземья";BackColor=Color.FromArgb(15,22,18);ForeColor=ink;Font=new Font("Segoe UI",10f);MinimumSize=new Size(1180,760);WindowState=FormWindowState.Maximized;StartPosition=FormStartPosition.CenterScreen;KeyPreview=true;SetStyle(ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);
            BuildTypes();LoadSprites();audio=new MciAudio(root);BuildUi();SetArenaPath();UpdateCards();UpdateInfo();
            double lastFrame=frameClock.Elapsed.TotalSeconds;timer.Interval=15;timer.Tick+=delegate{double now=frameClock.Elapsed.TotalSeconds;float dt=(float)Math.Max(.001,Math.Min(.05,now-lastFrame));lastFrame=now;if(paused||overlayPanel.Visible)return;if(waveRunning||enemies.Count>0||bolts.Count>0||bursts.Count>0||towers.Count>0||selectedType!=null){TickGame(dt*gameSpeed);field.Invalidate();}};timer.Start();FormClosed+=delegate{timer.Stop();audio.Dispose();towerBadgeFont.Dispose();foreach(Bitmap b in sceneCache)if(b!=null)b.Dispose();foreach(Bitmap b in heroes.Values)if(b!=null)b.Dispose();foreach(Bitmap b in foes.Values)if(b!=null)b.Dispose();};
            KeyDown+=delegate(object sender,KeyEventArgs e){if(e.KeyCode==Keys.Escape){selectedType=null;field.Invalidate();UpdateInfo();}else if(e.KeyCode==Keys.Space){if(paused)TogglePause();else StartWave();e.Handled=true;}else if(e.KeyCode==Keys.F11){fullscreenButton.PerformClick();}else if(e.KeyCode==Keys.P){TogglePause();}};
        }
        private void BuildTypes()
        {
            types.Add(new HeroType{Id="gondor",Name="Аста · анти-магический клинок",Icon="⚔",Price=70,Damage=17,Range=185,Rate=.85f,Description="Быстрый ближний удар",Special="На высшем уровне атакует три цели",Sprite="gondor",UpgradeCosts=new[]{80,125,190,290},Forms=new[]{"Аста","Чёрный бык","Демон-истребитель","Чёрная форма","Анти-магический Аста"},Colors=new[]{Color.FromArgb(85,57,48),Color.FromArgb(119,66,53),Color.FromArgb(158,72,58),Color.FromArgb(200,78,59),Color.FromArgb(238,112,79)}});
            types.Add(new HeroType{Id="elf",Name="Юно · магия ветра",Icon="✧",Price=100,Damage=28,Range=225,Rate=1.2f,Description="Дальний порыв ветра",Special="Пробивает строй врагов",Sprite="elf",UpgradeCosts=new[]{90,140,205,310},Forms=new[]{"Юно","Ветер Зефира","Дух ветра","Золотая корона","Духовой шквал"},Colors=new[]{Color.FromArgb(71,112,81),Color.FromArgb(91,143,91),Color.FromArgb(119,174,109),Color.FromArgb(157,202,136),Color.FromArgb(205,232,166)}});
            types.Add(new HeroType{Id="dwarf",Name="Магна · огненный шар",Icon="🔥",Price=125,Damage=45,Range=155,Rate=1.05f,Description="Сильный огненный удар",Special="Взрыв задевает соседние цели",Sprite="dwarf",UpgradeCosts=new[]{95,145,215,320},Forms=new[]{"Магна","Красная нить","Пылающий мяч","Огненная броня","Великий огненный шар"},Colors=new[]{Color.FromArgb(161,73,46),Color.FromArgb(194,87,47),Color.FromArgb(223,111,49),Color.FromArgb(240,145,58),Color.FromArgb(255,199,86)}});
            types.Add(new HeroType{Id="aura",Name="Ванесса · красная нить",Icon="✦",Price=115,Damage=0,Range=185,Rate=0,Description="Аура скорости или урона",Special="Усиленная широкая аура",Sprite="aura",UpgradeCosts=new[]{95,145,220,330},Forms=new[]{"Ванесса","Красная нить судьбы","Нить защиты","Алая судьба","Нить судьбы: сильная аура"},Colors=new[]{Color.FromArgb(143,59,82),Color.FromArgb(177,70,101),Color.FromArgb(205,88,119),Color.FromArgb(227,127,145),Color.FromArgb(255,178,187)}});
            types.Add(new HeroType{Id="ice",Name="Ноэль · магия воды",Icon="❄",Price=120,Damage=18,Range=192,Rate=1.25f,Description="Водный залп замедляет",Special="Почти полностью замораживает цель",Sprite="ice",UpgradeCosts=new[]{95,145,215,320},Forms=new[]{"Ноэль","Серебряное копьё","Водная броня","Морской дракон","Валькирия: ледяной плен"},Colors=new[]{Color.FromArgb(83,135,166),Color.FromArgb(102,162,194),Color.FromArgb(129,189,214),Color.FromArgb(170,217,232),Color.FromArgb(218,249,255)}});
        }
        private void LoadSprites()
        {
            foreach(HeroType t in types)heroes[t.Sprite]=LoadBitmap(Path.Combine(root,"Assets","Heroes",t.Sprite+".png"),150,246);
            foreach(string id in enemyIds)foes[id]=LoadBitmap(Path.Combine(root,"Assets","Enemies",id+".png"),186,246);
        }
        private Bitmap LoadBitmap(string file,int width,int height){if(!File.Exists(file))return null;using(Image src=Image.FromFile(file)){Bitmap b=new Bitmap(width,height,PixelFormat.Format32bppPArgb);using(Graphics g=Graphics.FromImage(b)){g.Clear(Color.Transparent);g.CompositingMode=CompositingMode.SourceCopy;g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.SmoothingMode=SmoothingMode.HighQuality;g.DrawImage(src,new Rectangle(0,0,width,height));}return b;}}

        private void BuildUi()
        {
            TableLayoutPanel rootLayout=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=1,RowCount=2,Margin=new Padding(0),Padding=new Padding(0),BackColor=BackColor};rootLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));rootLayout.RowStyles.Add(new RowStyle(SizeType.Absolute,100));rootLayout.RowStyles.Add(new RowStyle(SizeType.Percent,100));Controls.Add(rootLayout);
            Panel header=new Panel{Dock=DockStyle.Fill,BackColor=Color.FromArgb(18,27,22),Padding=new Padding(14,10,14,8)};
            Panel host=new Panel{Dock=DockStyle.Fill,Padding=new Padding(12),BackColor=BackColor};rootLayout.Controls.Add(header,0,0);rootLayout.Controls.Add(host,0,1);
            Label brand=new Label{Text="✦  РУБЕЖ СРЕДИЗЕМЬЯ\n     Чёрный клевер защищает Средиземье от Мордора",AutoSize=false,Width=465,Dock=DockStyle.Left,ForeColor=goldColor,Font=new Font("Georgia",15,FontStyle.Bold),TextAlign=ContentAlignment.MiddleLeft};header.Controls.Add(brand);
            FlowLayoutPanel stats=new FlowLayoutPanel{Dock=DockStyle.Fill,FlowDirection=FlowDirection.RightToLeft,WrapContents=false,Padding=new Padding(0,2,0,0)};header.Controls.Add(stats);
            fullscreenButton=MakeButton("⛶ Во весь экран",125,42);fullscreenButton.Click+=delegate{if(FormBorderStyle==FormBorderStyle.None){FormBorderStyle=FormBorderStyle.Sizable;WindowState=FormWindowState.Maximized;fullscreenButton.Text="⛶ Во весь экран";}else{FormBorderStyle=FormBorderStyle.None;WindowState=FormWindowState.Maximized;fullscreenButton.Text="⛶ Оконный режим";}};
            musicButton=MakeButton("♫ Музыка: выкл",128,42);musicButton.Click+=delegate{musicOn=!musicOn;if(musicOn){audio.PlayMusic(musicVolume.Value);musicButton.Text="♫ Музыка: вкл";}else{audio.StopMusic();musicButton.Text="♫ Музыка: выкл";}};
            stats.Controls.Add(fullscreenButton);stats.Controls.Add(VolumeBox("ЗВУК МАГИИ",false));stats.Controls.Add(VolumeBox("МУЗЫКА",true));stats.Controls.Add(musicButton);
            stats.Controls.Add(StatBox("АРЕНА",arenaLabel));stats.Controls.Add(StatBox("РУБЕЖ",livesLabel));stats.Controls.Add(StatBox("ВОЛНА",waveLabel));stats.Controls.Add(StatBox("ЗОЛОТО",goldLabel));
            goldLabel.Text=gold.ToString();waveLabel.Text="0/15";livesLabel.Text=lives.ToString();arenaLabel.Text=arenaShort[0];
            Panel side=new WarcraftPanel{Dock=DockStyle.Right,Width=360,Padding=new Padding(12),AutoScroll=true};host.Controls.Add(side);
            Panel board=new Panel{Dock=DockStyle.Fill,Padding=new Padding(0,0,12,0),BackColor=BackColor};host.Controls.Add(board);board.BringToFront();
            field.Dock=DockStyle.Fill;field.BackColor=Color.FromArgb(34,50,39);field.Paint+=PaintGame;field.MouseMove+=OnMouseMove;field.MouseLeave+=delegate{mouseWorld=new PointF(-100,-100);field.Invalidate();};field.MouseDown+=OnMouseDown;
            Panel fieldFrame=new Panel{Dock=DockStyle.Fill,Padding=new Padding(2),BackColor=Color.FromArgb(92,104,76)};board.Controls.Add(fieldFrame);fieldFrame.Controls.Add(field);
            Panel footer=new Panel{Dock=DockStyle.Bottom,Height=34,Padding=new Padding(10,6,10,4),BackColor=Color.FromArgb(25,34,28)};board.Controls.Add(footer);footer.BringToFront();statusLabel.Dock=DockStyle.Fill;statusLabel.ForeColor=muted;statusLabel.Text="Выбери героя справа, затем место на поле";statusLabel.Font=new Font("Segoe UI",9);footer.Controls.Add(statusLabel);
            int y=8;side.Controls.Add(SectionLabel("МАГИ-ЗАЩИТНИКИ",y));y+=32;
            cardList=new FlowLayoutPanel{Location=new Point(8,y),Width=side.ClientSize.Width-38,Height=395,Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right,FlowDirection=FlowDirection.TopDown,WrapContents=false,AutoScroll=false,BackColor=side.BackColor};side.Controls.Add(cardList);y+=400;
            startButton=MakeButton("▶  Начать волну",186,42);startButton.Location=new Point(8,y);startButton.Click+=delegate{StartWave();};side.Controls.Add(startButton);
            pauseButton=MakeButton("Ⅱ  Пауза",102,42);pauseButton.Location=new Point(199,y);pauseButton.Enabled=false;pauseButton.Click+=delegate{TogglePause();};side.Controls.Add(pauseButton);y+=49;
            Label speedLabel=new Label{Text="Темп",Left=9,Top=y+5,Width=80,Height=24,ForeColor=muted,Font=new Font("Segoe UI",9,FontStyle.Bold)};side.Controls.Add(speedLabel);
            speedSelector=new ComboBox{Left=79,Top=y,Width=132,Height=29,DropDownStyle=ComboBoxStyle.DropDownList,BackColor=Color.FromArgb(29,40,33),ForeColor=ink,Font=new Font("Segoe UI",9)};speedSelector.Items.AddRange(new object[]{"0,75×", "1×", "1,5×", "2×"});speedSelector.SelectedIndex=1;speedSelector.SelectedIndexChanged+=delegate{gameSpeed=new[]{.75f,1f,1.5f,2f}[Math.Max(0,speedSelector.SelectedIndex)];};side.Controls.Add(speedSelector);y+=36;
            selectedLabel=new Label{Location=new Point(9,y),Width=side.ClientSize.Width-34,Height=118,ForeColor=ink,Font=new Font("Segoe UI",9.5f),Text="Выбери героя, чтобы увидеть его способности.",Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right};side.Controls.Add(selectedLabel);y+=122;
            upgradeButton=MakeButton("Улучшить",(side.ClientSize.Width-42)/2,38);upgradeButton.Location=new Point(8,y);upgradeButton.Click+=delegate{Upgrade();};side.Controls.Add(upgradeButton);
            sellButton=MakeButton("Продать",(side.ClientSize.Width-42)/2,38);sellButton.Location=new Point(16+(side.ClientSize.Width-42)/2,y);sellButton.Click+=delegate{Sell();};side.Controls.Add(sellButton);y+=48;
            auraSpeedButton=MakeButton("Аура: скорость",(side.ClientSize.Width-42)/2,36);auraSpeedButton.Location=new Point(8,y);auraSpeedButton.Click+=delegate{SetAura("speed");};side.Controls.Add(auraSpeedButton);
            auraDamageButton=MakeButton("Аура: урон",(side.ClientSize.Width-42)/2,36);auraDamageButton.Location=new Point(16+(side.ClientSize.Width-42)/2,y);auraDamageButton.Click+=delegate{SetAura("damage");};side.Controls.Add(auraDamageButton);y+=48;
            side.Controls.Add(SectionLabel("СВОДКА РАЗВЕДКИ",y));y+=28;Label help=new Label{Location=new Point(9,y),Width=side.ClientSize.Width-34,Height=112,ForeColor=muted,Font=new Font("Segoe UI",9),Text="15 волн на каждой арене. Убивай отряды Мордора, получай золото и развивай магов. Четвёртый апгрейд открывает особую силу.\n\nКликни по герою на поле, чтобы выбрать его."};side.Controls.Add(help);
            overlayPanel=new Panel{Visible=true,BackColor=Color.FromArgb(218,9,16,13),Size=new Size(440,230)};
            overlayTitle=new Label{Text="Держи рубеж!",Dock=DockStyle.Top,Height=56,ForeColor=goldColor,Font=new Font("Georgia",22,FontStyle.Bold),TextAlign=ContentAlignment.MiddleCenter};
            overlayText=new Label{Text="Расставь магов рядом с дорогой и отбей 15 волн на каждой арене.",Dock=DockStyle.Top,Height=82,ForeColor=ink,Font=new Font("Segoe UI",11),TextAlign=ContentAlignment.MiddleCenter};
            Button overlayStart=MakeButton("Начать первую волну",300,42);overlayStart.Location=new Point(70,156);overlayStart.Click+=delegate{StartWave();};overlayPanel.Controls.Add(overlayStart);overlayPanel.Controls.Add(overlayText);overlayPanel.Controls.Add(overlayTitle);field.Controls.Add(overlayPanel);overlayPanel.BringToFront();
            pausePanel=new Panel{Visible=false,BackColor=Color.FromArgb(225,12,20,15),Size=new Size(280,92)};Label pausedText=new Label{Text="ПАУЗА",Dock=DockStyle.Fill,ForeColor=goldColor,Font=new Font("Georgia",25,FontStyle.Bold),TextAlign=ContentAlignment.MiddleCenter};pausePanel.Controls.Add(pausedText);field.Controls.Add(pausePanel);
            field.Resize+=delegate{overlayPanel.Left=(field.ClientSize.Width-overlayPanel.Width)/2;overlayPanel.Top=(field.ClientSize.Height-overlayPanel.Height)/2;};
            field.Resize+=delegate{pausePanel.Left=(field.ClientSize.Width-pausePanel.Width)/2;pausePanel.Top=(field.ClientSize.Height-pausePanel.Height)/2;};
        }
        private Control VolumeBox(string title,bool music)
        {
            Panel p=new Panel{Width=152,Height=54,Margin=new Padding(4,0,4,0),BackColor=Color.FromArgb(25,35,29)};Label l=new Label{Text=title,Left=6,Top=2,Width=140,Height=14,ForeColor=muted,Font=new Font("Segoe UI",7.5f,FontStyle.Bold)};p.Controls.Add(l);
            TrackBar slider=new TrackBar{Minimum=0,Maximum=music?100:1000,Value=music?35:450,TickFrequency=music?25:250,SmallChange=1,LargeChange=music?5:10,Height=30,Width=109,Left=0,Top=18,BackColor=p.BackColor};Label v=new Label{Text=music?slider.Value+"%":(slider.Value/10.0).ToString("0.0")+"%",Left=110,Top=21,Width=39,Height=20,ForeColor=goldColor,Font=new Font("Segoe UI",8)};
            slider.ValueChanged+=delegate{v.Text=music?slider.Value+"%":(slider.Value/10.0).ToString("0.0")+"%";if(music){musicVolume=slider;audio.SetMusicVolume(slider.Value);}else{effectVolume=slider;audio.SetEffectVolume(slider.Value);}};if(music){musicVolume=slider;musicValue=v;audio.SetMusicVolume(slider.Value);}else{effectVolume=slider;effectValue=v;audio.SetEffectVolume(slider.Value);}p.Controls.Add(slider);p.Controls.Add(v);return p;
        }
        private Control StatBox(string caption,Label value){Panel p=new Panel{Width=78,Height=50,Margin=new Padding(3,0,3,0),BackColor=Color.FromArgb(31,42,34)};value.Dock=DockStyle.Top;value.Height=27;value.TextAlign=ContentAlignment.MiddleCenter;value.ForeColor=goldColor;value.Font=new Font("Segoe UI",12,FontStyle.Bold);p.Controls.Add(value);Label l=new Label{Text=caption,Dock=DockStyle.Bottom,Height=16,TextAlign=ContentAlignment.MiddleCenter,ForeColor=muted,Font=new Font("Segoe UI",7.5f)};p.Controls.Add(l);return p;}
        private Label SectionLabel(string text,int top){return new Label{Text=text,Left=8,Top=top,Width=320,Height=24,ForeColor=goldColor,Font=new Font("Georgia",12,FontStyle.Bold)};}
        private Button MakeButton(string text,int width,int height){Button b=new Button{Text=text,Width=width,Height=height,FlatStyle=FlatStyle.Flat,BackColor=Color.FromArgb(53,53,46),ForeColor=Color.FromArgb(240,221,177),Font=new Font("Segoe UI",9,FontStyle.Bold),Cursor=Cursors.Hand,Margin=new Padding(4)};b.FlatAppearance.BorderColor=Color.FromArgb(168,132,74);b.FlatAppearance.BorderSize=1;b.FlatAppearance.MouseOverBackColor=Color.FromArgb(88,70,43);return b;}
        private void BuildCards(){cardList.SuspendLayout();cardList.Controls.Clear();foreach(HeroType type in types){HeroType t=type;Button b=MakeButton(t.Icon+"  "+t.Name+"\n"+t.Price+" ✦   ·   "+t.Description,cardList.Width-6,68);b.TextAlign=ContentAlignment.MiddleLeft;b.Padding=new Padding(12,3,6,3);b.Font=new Font("Segoe UI",9,FontStyle.Bold);b.Enabled=gold>=t.Price;b.BackColor=selectedType==t?Color.FromArgb(74,69,43):Color.FromArgb(29,40,33);b.Click+=delegate{selectedType=t;selectedTower=null;UpdateInfo();field.Invalidate();BuildCards();};cardList.Controls.Add(b);}cardList.ResumeLayout();}
        private void UpdateCards(){goldLabel.Text=gold.ToString();BuildCards();}
        private void UpdateInfo()
        {
            bool aura=selectedTower!=null&&selectedTower.Type.Id=="aura";auraSpeedButton.Visible=aura;auraDamageButton.Visible=aura;
            if(selectedTower==null){upgradeButton.Enabled=false;sellButton.Enabled=false;selectedLabel.Text=selectedType==null?"Выбери героя, чтобы увидеть его способности.":selectedType.Name+"\n\nНаведи курсор на поле — призрак покажет место установки.";return;}
            Tower t=selectedTower;HeroType d=t.Type;float dm,sp;Buff(t,out dm,out sp);string next=t.Level<4?"\nСледующий уровень: "+d.Forms[t.Level+1]:"\nОсобенность: "+d.Special;
            string stat=d.Id=="aura"?"Радиус "+(int)t.Range+" · усиление "+(int)(t.Power*100)+"% к "+(t.Aura=="damage"?"урону":"скорости атаки"):"Урон "+(int)(t.Damage*dm)+" · дальность "+(int)t.Range+"\nСкорость "+(1f/t.Rate*sp).ToString("0.0")+" выстр./с";
            selectedLabel.Text=d.Forms[t.Level]+"  ·  уровень "+(t.Level+1)+"\n"+stat+next;upgradeButton.Enabled=t.Level<4&&gold>=d.UpgradeCosts[t.Level];upgradeButton.Text=t.Level<4?"Улучшить · "+d.UpgradeCosts[t.Level]+" ✦":"Максимум";sellButton.Enabled=true;
            auraSpeedButton.BackColor=t.Aura=="speed"?Color.FromArgb(74,87,49):Color.FromArgb(37,48,39);auraDamageButton.BackColor=t.Aura=="damage"?Color.FromArgb(110,78,38):Color.FromArgb(37,48,39);
        }
        private void UpdateStatus(string s){statusLabel.Text=s;}
        private void SetArenaPath()
        {
            if(arenaIndex%3==0)path=ScalePath(new[]{new PointF(-30,110),new PointF(145,110),new PointF(180,112),new PointF(205,140),new PointF(205,230),new PointF(235,258),new PointF(360,258),new PointF(405,250),new PointF(425,220),new PointF(425,148),new PointF(452,112),new PointF(495,104),new PointF(590,104),new PointF(620,130),new PointF(620,270),new PointF(650,306),new PointF(750,306),new PointF(815,306),new PointF(840,280),new PointF(840,205),new PointF(870,174),new PointF(930,174),new PointF(1020,174),new PointF(1050,200),new PointF(1050,445),new PointF(1030,477),new PointF(1000,490),new PointF(1050,510),new PointF(1230,510)});
            else if(arenaIndex%3==1)path=ScalePath(new[]{new PointF(-25,145),new PointF(125,145),new PointF(170,160),new PointF(205,205),new PointF(205,315),new PointF(235,350),new PointF(330,360),new PointF(440,360),new PointF(475,335),new PointF(490,275),new PointF(490,180),new PointF(520,140),new PointF(565,130),new PointF(650,130),new PointF(680,160),new PointF(680,365),new PointF(720,410),new PointF(825,420),new PointF(915,420),new PointF(950,395),new PointF(965,345),new PointF(965,295),new PointF(1000,270),new PointF(1080,270),new PointF(1230,270)});
            else path=ScalePath(new[]{new PointF(-30,500),new PointF(120,500),new PointF(160,480),new PointF(190,440),new PointF(190,325),new PointF(220,285),new PointF(270,270),new PointF(370,270),new PointF(410,300),new PointF(420,355),new PointF(420,425),new PointF(455,470),new PointF(520,490),new PointF(630,490),new PointF(670,465),new PointF(690,405),new PointF(690,300),new PointF(725,255),new PointF(790,230),new PointF(890,230),new PointF(930,255),new PointF(950,310),new PointF(950,370),new PointF(985,410),new PointF(1050,425),new PointF(1120,425),new PointF(1230,380)});
            arenaLabel.Text=arenaShort[arenaIndex%3];BuildMotionPath();
        }
        private PointF[] ScalePath(PointF[] p){PointF[] q=new PointF[p.Length];for(int i=0;i<p.Length;i++)q[i]=new PointF(p[i].X*1.08f,p[i].Y*1.02f);return q;}
        private void StartWave()
        {
            if(waveRunning)return;if(gameOver){ResetGame();return;}
            if(paused){paused=false;pausePanel.Visible=false;pauseButton.Text="Ⅱ  Пауза";}
            if(stageReady){int refund=0;foreach(Tower t in towers)refund+=(int)(t.Invested*.55f);gold+=refund+220;towers.Clear();enemies.Clear();bolts.Clear();selectedTower=null;selectedType=null;lives=15;arenaIndex++;waveInArena=0;stageReady=false;SetArenaPath();UpdateStatus("Новая арена. За переход получено "+(refund+220)+" золота.");}
            waveInArena++;totalWaves++;waveRunning=true;remainingSpawns=6+waveInArena*2;spawnCountdown=.25f;overlayPanel.Visible=false;pauseButton.Enabled=true;startButton.Enabled=false;startButton.Text="Волна идёт…";waveLabel.Text=waveInArena+"/15";arenaLabel.Text=arenaShort[arenaIndex%3];livesLabel.Text=lives.ToString();UpdateCards();UpdateInfo();field.Invalidate();
        }
        private void ResetGame(){gold=360;lives=15;totalWaves=0;waveInArena=0;arenaIndex=0;stageReady=false;gameOver=false;waveRunning=false;paused=false;pausePanel.Visible=false;pauseButton.Enabled=false;pauseButton.Text="Ⅱ  Пауза";remainingSpawns=0;enemies.Clear();towers.Clear();bolts.Clear();bursts.Clear();SetArenaPath();waveLabel.Text="0/15";livesLabel.Text="15";goldLabel.Text="360";startButton.Text="▶  Начать волну";startButton.Enabled=true;overlayTitle.Text="Держи рубеж!";overlayText.Text="Расставь магов рядом с дорогой и отбей 15 волн на каждой арене.";overlayPanel.Visible=true;UpdateCards();UpdateInfo();field.Invalidate();}
        private void TogglePause(){if(totalWaves==0||gameOver)return;paused=!paused;pausePanel.Visible=paused;pauseButton.Text=paused?"▶  Продолжить":"Ⅱ  Пауза";UpdateStatus(paused?"Игра на паузе.":"Игра продолжается.");field.Invalidate();}
        private void Spawn()
        {
            int ordinal=remainingSpawns--;string kind;if(waveInArena<3)kind=ordinal%2==0?"goblin":"orc";else if(waveInArena<6)kind=ordinal%3==0?"warg":"uruk";else if(waveInArena<10)kind=ordinal%4==0?"troll":"uruk";else kind=ordinal%5==0?"nazgul":ordinal%3==0?"troll":"uruk";
            bool boss=ordinal==0&&waveInArena%5==0;if(boss)kind=waveInArena>=15?"nazgul":"troll";int k=Array.IndexOf(enemyIds,kind);float hp=36+waveInArena*18+arenaIndex*55+(boss?145:0),speed=kind=="warg"?82:kind=="troll"?31:kind=="nazgul"?61:kind=="goblin"?62:49;int[] reward={20,24,30,34,42,54};int r=reward[k];if(boss)r=100+arenaIndex*30+waveInArena*4;else r=(int)Math.Round(r*(1+arenaIndex*.15+waveInArena*.035));
            enemies.Add(new Enemy{Kind=kind,Name=enemyNames[k],Distance=0,Speed=speed+Math.Min(waveInArena,18)+arenaIndex*2,Hp=hp,MaxHp=hp,Reward=r,Radius=(kind=="troll"||kind=="nazgul")?19:kind=="uruk"?15:12,Boss=boss,Phase=(float)new Random(Guid.NewGuid().GetHashCode()).NextDouble()*6});
        }
        private void TickGame(float dt)
        {
            clock+=dt;
            if(waveRunning){spawnCountdown-=dt;if(spawnCountdown<=0&&remainingSpawns>0){Spawn();spawnCountdown=Math.Max(.38f,1.02f-waveInArena*.025f);}
                for(int i=enemies.Count-1;i>=0;i--){Enemy e=enemies[i];float slow=e.SlowUntil>clock?e.Slow:1;e.Distance+=e.Speed*slow*dt;PositionEnemy(e);if(e.Distance>=PathLength()){enemies.RemoveAt(i);lives--;livesLabel.Text=lives.ToString();UpdateStatus(e.Name+" прорвался к рубежу!");if(lives<=0){waveRunning=false;gameOver=true;paused=false;pausePanel.Visible=false;pauseButton.Enabled=false;startButton.Enabled=true;startButton.Text="Начать заново";overlayTitle.Text="Рубеж пал";overlayText.Text="Остаток сил отступил. Перестрой оборону и попробуй ещё раз.";overlayPanel.Visible=true;}}}
                if(remainingSpawns<=0&&enemies.Count==0){waveRunning=false;int bonus=80+arenaIndex*25+waveInArena*5;gold+=bonus;goldLabel.Text=gold.ToString();startButton.Enabled=true;if(waveInArena>=15){stageReady=true;startButton.Text="Перейти на следующую арену";overlayTitle.Text="Арена очищена!";overlayText.Text="15 волн отбиты. Следующая карта начнётся с новой расстановки.";overlayPanel.Visible=true;}else startButton.Text="▶  Начать волну "+(waveInArena+1)+"/15";UpdateStatus("Волна отбита · награда +"+bonus+" золота.");UpdateCards();}}
            foreach(Tower t in towers){if(t.Type.Id=="aura")continue;t.Cooldown-=dt;if(t.Cooldown<=0){float dm,sp;Buff(t,out dm,out sp);List<Enemy> targets=enemies.FindAll(x=>Distance(t.X,t.Y,x.X,x.Y)<=t.Range);targets.Sort(delegate(Enemy a,Enemy b){return b.Distance.CompareTo(a.Distance);});int n=t.Type.Id=="gondor"&&t.Level>=4?3:1;if(targets.Count>0){t.LastShot=clock;audio.PlayEffect(t.Type.Id);for(int j=0;j<Math.Min(n,targets.Count);j++){Bolt p=new Bolt{Source=t,Target=targets[j],X=t.X,Y=t.Y-20,Damage=t.Damage*dm,Speed=440,Type=t.Type.Id,Slow=t.Type.Id=="ice"?(t.Level>=4?.12f:.55f):1,SlowTime=t.Type.Id=="ice"?1.5f:0,Freeze=t.Type.Id=="ice"&&t.Level>=4?.7f:0,Splash=t.Level>=4&&t.Type.Id=="dwarf"?52:0,Pierce=t.Level>=4&&t.Type.Id=="elf"?3:0};bolts.Add(p);}t.Cooldown=t.Rate/sp;}}}
            for(int i=bolts.Count-1;i>=0;i--){Bolt b=bolts[i];if(b.Target==null||!enemies.Contains(b.Target)){bolts.RemoveAt(i);continue;}float dx=b.Target.X-b.X,dy=b.Target.Y-b.Y,d=(float)Math.Sqrt(dx*dx+dy*dy),step=b.Speed*dt;if(d<=step+b.Target.Radius){Impact(b,b.Target);if(b.Target==null)bolts.RemoveAt(i);}else{b.X+=dx/d*step;b.Y+=dy/d*step;}}
            for(int i=bursts.Count-1;i>=0;i--){bursts[i].Life+=dt;if(bursts[i].Life>=bursts[i].Duration)bursts.RemoveAt(i);}if(selectedTower!=null&&!towers.Contains(selectedTower)){selectedTower=null;UpdateInfo();}
        }
        private void BuildMotionPath(){using(GraphicsPath p=CreateRoute()){p.Flatten(null,.8f);motionPath=p.PathPoints;motionDistances=new float[motionPath.Length];routeLength=0;for(int i=1;i<motionPath.Length;i++){routeLength+=Distance(motionPath[i-1].X,motionPath[i-1].Y,motionPath[i].X,motionPath[i].Y);motionDistances[i]=routeLength;}}}
        private float PathLength(){return routeLength;}
        private void PositionEnemy(Enemy e){if(motionPath.Length<2)return;int i=Math.Max(0,Math.Min(e.PathSegment,motionPath.Length-2));while(i<motionPath.Length-2&&e.Distance>motionDistances[i+1])i++;e.PathSegment=i;PointF a=motionPath[i],b=motionPath[i+1];float len=motionDistances[i+1]-motionDistances[i],u=len<=0?0:(e.Distance-motionDistances[i])/len;u=Math.Max(0,Math.Min(1,u));e.X=a.X+(b.X-a.X)*u;e.Y=a.Y+(b.Y-a.Y)*u;}
        private static float Distance(float x1,float y1,float x2,float y2){float x=x1-x2,y=y1-y2;return(float)Math.Sqrt(x*x+y*y);}
        private void Impact(Bolt b,Enemy e)
        {
            if(!enemies.Contains(e)||!b.Hit.Add(e))return;e.Hp-=b.Damage;if(b.Slow<1){e.Slow=Math.Min(e.Slow,b.Slow);e.SlowUntil=clock+b.SlowTime;}if(b.Freeze>0){e.Slow=.04f;e.SlowUntil=clock+b.Freeze;}bursts.Add(new Burst{X=e.X,Y=e.Y,Life=0,Duration=.24f,Color=TypeColor(b.Type,b.Source.Level)});if(e.Hp<=0)Defeat(e);
            if(b.Splash>0){foreach(Enemy other in enemies.ToArray())if(other!=e&&Distance(other.X,other.Y,e.X,e.Y)<b.Splash){other.Hp-=b.Damage*.55f;if(other.Hp<=0)Defeat(other);}}
            if(b.Pierce>0){b.Pierce--;b.Target=null;Enemy next=null;float best=float.MaxValue;foreach(Enemy other in enemies)if(!b.Hit.Contains(other)&&Distance(other.X,other.Y,b.X,b.Y)<90&&other.Distance<best){next=other;best=other.Distance;}if(next!=null)b.Target=next;}
            else b.Target=null;
        }
        private void Defeat(Enemy e){if(!enemies.Remove(e))return;audio.PlayDeath();gold+=e.Reward;goldLabel.Text=gold.ToString();bursts.Add(new Burst{X=e.X,Y=e.Y,Life=0,Duration=.38f,Color=Color.FromArgb(241,201,110)});UpdateCards();UpdateStatus(e.Name+" повержен · +"+e.Reward+" золота.");}
        private void Buff(Tower t,out float damage,out float speed){damage=1;speed=1;foreach(Tower a in towers){if(a==t||a.Type.Id!="aura"||Distance(a.X,a.Y,t.X,t.Y)>a.Range)continue;if(a.Aura=="damage")damage*=1+a.Power;else speed*=1+a.Power;}}
        private void Upgrade(){if(selectedTower==null||selectedTower.Level>=4)return;Tower t=selectedTower;HeroType d=t.Type;int cost=d.UpgradeCosts[t.Level];if(gold<cost)return;gold-=cost;t.Invested+=cost;t.Level++;if(d.Id=="aura"){t.Range+=28;t.Power=new[]{.3f,.4f,.52f,.66f,.82f}[t.Level];}else{t.Damage*=d.Id=="gondor"?1.34f:1.4f;t.Range+=16;t.Rate*=d.Id=="gondor"?.82f:.9f;}UpdateCards();UpdateInfo();field.Invalidate();UpdateStatus(d.Forms[t.Level]+" · улучшение завершено.");}
        private void Sell(){if(selectedTower==null)return;int refund=(int)(selectedTower.Invested*.65f);towers.Remove(selectedTower);selectedTower=null;gold+=refund;UpdateCards();UpdateInfo();field.Invalidate();UpdateStatus("Башня разобрана · возвращено "+refund+" золота.");}
        private void SetAura(string mode){if(selectedTower==null||selectedTower.Type.Id!="aura")return;selectedTower.Aura=mode;UpdateInfo();field.Invalidate();UpdateStatus("Аура выбрана: "+(mode=="damage"?"урон":"скорость атаки")+".");}
        private static Color TypeColor(string id,int level){Color[] c=id=="gondor"?new[]{Color.OrangeRed,Color.Orange}:id=="elf"?new[]{Color.LightGreen,Color.Cyan}:id=="dwarf"?new[]{Color.Orange,Color.Gold}:id=="ice"?new[]{Color.LightCyan,Color.DeepSkyBlue}:new[]{Color.HotPink,Color.Pink};return c[Math.Min(level>=4?1:0,c.Length-1)];}
        private void OnMouseMove(object sender,MouseEventArgs e){mouseWorld=ToWorld(e.Location);if(selectedType!=null)field.Invalidate();}
        private void OnMouseDown(object sender,MouseEventArgs e)
        {
            if(e.Button!=MouseButtons.Left)return;PointF p=ToWorld(e.Location);for(int i=towers.Count-1;i>=0;i--)if(Distance(towers[i].X,towers[i].Y,p.X,p.Y)<32){selectedTower=towers[i];selectedType=null;UpdateCards();UpdateInfo();field.Invalidate();return;}
            if(selectedType!=null){Place(p.X,p.Y);return;}selectedTower=null;UpdateInfo();field.Invalidate();
        }
        private PointF ToWorld(Point p){if(scale<=0)return new PointF(-100,-100);return new PointF((p.X-offsetX)/scale,(p.Y-offsetY)/scale);}
        private bool NearPath(float x,float y){for(int i=1;i<path.Length;i++)if(PointSegmentDistance(x,y,path[i-1],path[i])<64)return true;return false;}
        private static float PointSegmentDistance(float x,float y,PointF a,PointF b){float dx=b.X-a.X,dy=b.Y-a.Y,l=dx*dx+dy*dy,t=l==0?0:Math.Max(0,Math.Min(1,((x-a.X)*dx+(y-a.Y)*dy)/l));return Distance(x,y,a.X+t*dx,a.Y+t*dy);}
        private bool ValidSpot(float x,float y){if(x<35||x>WorldW-35||y<35||y>WorldH-35||NearPath(x,y))return false;foreach(Tower t in towers)if(Distance(x,y,t.X,t.Y)<62)return false;return true;}
        private void Place(float x,float y)
        {
            if(selectedType==null)return;if(gold<selectedType.Price){UpdateStatus("Не хватает золота.");return;}if(!ValidSpot(x,y)){UpdateStatus("Красное место — слишком близко к дороге или другой башне.");return;}
            Tower t=new Tower{Type=selectedType,X=x,Y=y,Damage=selectedType.Damage,Range=selectedType.Range,Rate=selectedType.Rate,Invested=selectedType.Price};towers.Add(t);gold-=selectedType.Price;selectedTower=t;selectedType=null;UpdateCards();UpdateInfo();UpdateStatus("Маг занял позицию. Развивай его по мере волн.");field.Invalidate();
        }
        private void PaintGame(object sender,PaintEventArgs e)
        {
            Graphics g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;g.InterpolationMode=InterpolationMode.Bilinear;g.PixelOffsetMode=PixelOffsetMode.Default;float sx=field.ClientSize.Width/WorldW,sy=field.ClientSize.Height/WorldH;scale=Math.Min(sx,sy);offsetX=(field.ClientSize.Width-WorldW*scale)/2;offsetY=(field.ClientSize.Height-WorldH*scale)/2;g.TranslateTransform(offsetX,offsetY);g.ScaleTransform(scale,scale);
            g.DrawImage(GetSceneCache(arenaIndex%3),new RectangleF(0,0,WorldW,WorldH));foreach(Tower t in towers)DrawTower(g,t);foreach(Enemy x in enemies)DrawEnemy(g,x);foreach(Bolt b in bolts)DrawBolt(g,b);foreach(Burst b in bursts)DrawBurst(g,b);if(selectedType!=null&&mouseWorld.X>=0)DrawPreview(g,mouseWorld.X,mouseWorld.Y);
        }
        private Bitmap GetSceneCache(int scene)
        {
            if(sceneCache[scene]!=null)return sceneCache[scene];const int qualityScale=2;Bitmap image=new Bitmap((int)WorldW*qualityScale,(int)WorldH*qualityScale,PixelFormat.Format32bppPArgb);using(Graphics g=Graphics.FromImage(image)){g.ScaleTransform(qualityScale,qualityScale);g.SmoothingMode=SmoothingMode.AntiAlias;g.InterpolationMode=InterpolationMode.HighQualityBicubic;DrawTerrain(g);DrawRoad(g);DrawGates(g);}sceneCache[scene]=image;return image;
        }
        private void DrawTerrain(Graphics g)
        {
            int scene=arenaIndex%3;Color c1=scene==0?Color.FromArgb(56,79,58):scene==1?Color.FromArgb(72,53,45):Color.FromArgb(75,111,133);Color c3=scene==0?Color.FromArgb(74,78,47):scene==1?Color.FromArgb(90,65,49):Color.FromArgb(128,151,158);
            using(LinearGradientBrush bg=new LinearGradientBrush(new RectangleF(0,0,WorldW,WorldH),c1,c3,35f))g.FillRectangle(bg,0,0,WorldW,WorldH);
            using(SolidBrush hill=new SolidBrush(Color.FromArgb(20,15,25,18)))for(int i=0;i<9;i++)g.FillEllipse(hill,i*160-60,65+(i%4)*55,220,100);
            Random r=new Random(93+arenaIndex*19);for(int i=0;i<210;i++){float x=(float)r.NextDouble()*WorldW,y=(float)r.NextDouble()*WorldH;if(NearPath(x,y))continue;if(scene==0){using(Pen p=new Pen(i%3==0?Color.FromArgb(76,167,175,112):Color.FromArgb(52,27,50,37),1.2f)){g.DrawLine(p,x-5,y+3,x-1,y-4-r.Next(0,8));g.DrawLine(p,x,y+2,x+5,y-4);}}else if(scene==1){using(Pen p=new Pen(i%5==0?Color.FromArgb(102,211,127,67):Color.FromArgb(70,40,32,28),1.4f)){g.DrawLine(p,x-5,y+2,x-1,y-2);g.DrawLine(p,x-1,y-2,x+5,y-4);}}else{using(SolidBrush b=new SolidBrush(Color.FromArgb(75,208,233,237)))g.FillPolygon(b,new[]{new PointF(x,y-5),new PointF(x+3,y),new PointF(x,y+4),new PointF(x-3,y)});}}
            for(int i=0;i<58;i++){float x=(i*193+41)%WorldW,y=(i*127+56)%WorldH;if(NearPath(x,y))continue;int h=22+(i*13%36);if(scene==0)DrawPine(g,x,y,h,i%2==0);else if(scene==1)DrawRuin(g,x,y,h,i);else DrawIceRock(g,x,y,h,i);}
        }
        private void DrawPine(Graphics g,float x,float y,float h,bool light)
        {
            Color c=light?Color.FromArgb(43,72,55):Color.FromArgb(31,58,47);Color mid=light?Color.FromArgb(49,83,62):Color.FromArgb(37,68,53);using(SolidBrush b=new SolidBrush(c))g.FillPolygon(b,new[]{new PointF(x,y-h),new PointF(x-h*.58f,y+h*.22f),new PointF(x+h*.58f,y+h*.22f)});using(SolidBrush b=new SolidBrush(mid))g.FillPolygon(b,new[]{new PointF(x,y-h*.62f),new PointF(x-h*.46f,y+h*.04f),new PointF(x+h*.46f,y+h*.04f)});using(SolidBrush b=new SolidBrush(Color.FromArgb(55,95,68)))g.FillPolygon(b,new[]{new PointF(x,y-h*.28f),new PointF(x-h*.31f,y+h*.22f),new PointF(x+h*.31f,y+h*.22f)});using(SolidBrush trunk=new SolidBrush(Color.FromArgb(107,83,53)))g.FillRectangle(trunk,x-2,y+h*.18f,4,h*.22f);using(Pen rim=new Pen(Color.FromArgb(62,153,168,114),1.3f)){g.DrawLine(rim,x,y-h+3,x-h*.42f,y);g.DrawLine(rim,x-h*.42f,y,x+h*.45f,y);g.DrawLine(rim,x,y-h*.55f,x-h*.32f,y+.03f*h);g.DrawLine(rim,x-h*.32f,y+.03f*h,x+h*.32f,y+.03f*h);}
        }
        private void DrawRuin(Graphics g,float x,float y,float h,int i){Color c=Color.FromArgb(70,68+i%3*4,55+i%3*4);using(SolidBrush b=new SolidBrush(c))g.FillPolygon(b,new[]{new PointF(x-h*.5f,y+h*.2f),new PointF(x-h*.28f,y-h*.4f),new PointF(x+h*.26f,y-h*.62f),new PointF(x+h*.52f,y+h*.2f)});using(Pen crack=new Pen(Color.FromArgb(130,213,114,65),1))g.DrawLine(crack,x-3,y,x+2,y-8);}
        private void DrawIceRock(Graphics g,float x,float y,float h,int i){using(SolidBrush b=new SolidBrush(Color.FromArgb(75,44+i%3*7,79+i%3*7,89+i%3*7)))g.FillPolygon(b,new[]{new PointF(x,y-h),new PointF(x-h*.55f,y+h*.25f),new PointF(x+h*.48f,y+h*.25f)});using(Pen glint=new Pen(Color.FromArgb(105,214,241,245),1))g.DrawLine(glint,x,y-h,x-4,y-2);}
        private void DrawRoad(Graphics g)
        {
            using(GraphicsPath p=CreateRoute()){using(Pen a=new Pen(Color.FromArgb(45,39,31),66){LineJoin=LineJoin.Round,StartCap=LineCap.Round,EndCap=LineCap.Round})g.DrawPath(a,p);using(Pen b=new Pen(Color.FromArgb(129,117,86),55){LineJoin=LineJoin.Round,StartCap=LineCap.Round,EndCap=LineCap.Round})g.DrawPath(b,p);using(Pen c=new Pen(Color.FromArgb(157,145,110),43){LineJoin=LineJoin.Round,StartCap=LineCap.Round,EndCap=LineCap.Round})g.DrawPath(c,p);using(Pen d=new Pen(Color.FromArgb(181,169,132),1.5f){DashPattern=new[]{1.2f,7f},LineJoin=LineJoin.Round})g.DrawPath(d,p);}
            using(Pen edge=new Pen(Color.FromArgb(40,242,224,169),2)){edge.DashPattern=new[]{4f,9f};using(GraphicsPath p=CreateRoute())g.DrawPath(edge,p);}
        }
        private GraphicsPath CreateRoute(){GraphicsPath p=new GraphicsPath();p.AddCurve(path,.16f);return p;}
        private void DrawGates(Graphics g)
        {
            float y=Math.Max(22,Math.Min(610,path[1].Y-38));using(SolidBrush dark=new SolidBrush(Color.FromArgb(66,48,31)))g.FillRectangle(dark,5,y-24,38,63);using(SolidBrush gate=new SolidBrush(Color.FromArgb(197,168,104)))g.FillRectangle(gate,11,y-19,27,54);using(SolidBrush hole=new SolidBrush(Color.FromArgb(30,29,23)))g.FillRectangle(hole,19,y-4,11,39);using(SolidBrush text=new SolidBrush(Color.FromArgb(241,213,151)))using(Font f=new Font("Georgia",11,FontStyle.Bold))g.DrawString(arenaIndex%3==0?"ЧЁРНЫЕ ВРАТА":arenaIndex%3==1?"ПЕПЕЛЬНЫЙ ПРОХОД":"СЕВЕРНЫЙ ПРОХОД",f,text,8,y-43);
            float ey=path[path.Length-2].Y;using(SolidBrush stone=new SolidBrush(Color.FromArgb(178,159,111)))g.FillRectangle(stone,WorldW-45,ey-27,35,58);using(SolidBrush dark2=new SolidBrush(Color.FromArgb(32,34,29)))g.FillRectangle(dark2,WorldW-34,ey-16,13,47);
        }
        private void DrawTower(Graphics g,Tower t)
        {
            HeroType d=t.Type;Color col=TypeColor(d.Id,t.Level);if(t==selectedTower)using(Pen range=new Pen(Color.FromArgb(96,239,215,141),1.7f))g.DrawEllipse(range,t.X-t.Range,t.Y-t.Range,t.Range*2,t.Range*2);
            float bob=(float)Math.Sin(clock*3.2+t.X*.025f)*1.6f,attack=Math.Max(0,1-(clock-t.LastShot)/.23f);using(SolidBrush shadow=new SolidBrush(Color.FromArgb(125,7,11,8)))g.FillEllipse(shadow,t.X-24,t.Y-6,48,17);using(SolidBrush baseB=new SolidBrush(Color.FromArgb(105,97,68)))g.FillEllipse(baseB,t.X-20,t.Y-7,40,12);using(Pen baseEdge=new Pen(Color.FromArgb(218,212,188,133),1.5f))g.DrawEllipse(baseEdge,t.X-18,t.Y-8,36,11);
            if(d.Id=="aura"){Color aura=t.Aura=="damage"?Color.FromArgb(52,239,184,75):Color.FromArgb(48,137,221,128);using(Pen p=new Pen(aura,8+(float)Math.Sin(clock*4)*1.3f))g.DrawEllipse(p,t.X-t.Range,t.Y-t.Range,t.Range*2,t.Range*2);}else{float dm,sp;Buff(t,out dm,out sp);if(dm>1||sp>1)using(Pen p=new Pen(dm>1?Color.FromArgb(190,255,202,89):Color.FromArgb(190,151,229,134),2.5f))g.DrawEllipse(p,t.X-24,t.Y-10,48,16);}
            float h=70+t.Level*3,w=h*.57f;Image im=heroes[d.Sprite];if(im!=null){GraphicsState st=g.Save();g.TranslateTransform(t.X,t.Y+2+bob);g.RotateTransform((float)Math.Sin(clock*2.8+t.X*.02f)*1.2f-attack*5);g.DrawImage(im,new RectangleF(-w/2,-h,w,h));g.Restore(st);}
            if(t.Level>=1)using(Pen p=new Pen(col,2.4f))g.DrawArc(p,t.X-27,t.Y-45,54,31,205,130);if(t.Level>=2)using(SolidBrush b=new SolidBrush(Color.FromArgb(160,col)))for(int i=0;i<4;i++){float a=(float)(clock*1.7+i*Math.PI/2);g.FillEllipse(b,t.X+(float)Math.Cos(a)*29-2,t.Y-28+(float)Math.Sin(a)*16-2,4,4);}if(t.Level>=4)using(Pen p=new Pen(Color.FromArgb(210,col),3))g.DrawEllipse(p,t.X-32,t.Y-73,64,64);
            using(SolidBrush badge=new SolidBrush(Color.FromArgb(221,16,22,18)))g.FillEllipse(badge,t.X-18,t.Y-1,36,16);using(SolidBrush badgeText=new SolidBrush(Color.FromArgb(255,238,224,176)))g.DrawString("L"+(t.Level+1),towerBadgeFont,badgeText,t.X-9,t.Y+1);if(attack>0)using(Pen glow=new Pen(Color.FromArgb((int)(attack*210),col),3+attack*3)){glow.StartCap=LineCap.Round;glow.EndCap=LineCap.Round;g.DrawLine(glow,t.X+8,t.Y-32,t.X+25+attack*11,t.Y-43);}
        }
        private void DrawEnemy(Graphics g,Enemy e)
        {
            Image im=foes.ContainsKey(e.Kind)?foes[e.Kind]:null;float bob=(float)Math.Sin(clock*8+e.Phase)*2.4f,w=e.Boss?62:48,h=e.Boss?82:64;using(SolidBrush sh=new SolidBrush(Color.FromArgb(130,8,12,10)))g.FillEllipse(sh,e.X-w*.37f,e.Y+8,w*.74f,12);if(im!=null)g.DrawImage(im,new RectangleF(e.X-w/2,e.Y-h/2+bob,w,h));else using(SolidBrush body=new SolidBrush(Color.SaddleBrown))g.FillEllipse(body,e.X-12,e.Y-19,24,36);
            if(e.Boss)using(Pen p=new Pen(Color.FromArgb(160,180,86,202),2))g.DrawEllipse(p,e.X-w*.55f,e.Y-h*.5f+bob,w*1.1f,h*1.1f);float bw=e.Boss?52:38;using(SolidBrush back=new SolidBrush(Color.FromArgb(210,35,25,22)))g.FillRectangle(back,e.X-bw/2,e.Y-h/2-8,bw,5);using(SolidBrush hp=new SolidBrush(e.Hp/e.MaxHp>.45f?Color.FromArgb(208,102,166,91):Color.FromArgb(220,198,72,56)))g.FillRectangle(hp,e.X-bw/2,e.Y-h/2-8,bw*Math.Max(0,e.Hp/e.MaxHp),5);if(e.SlowUntil>clock)using(Pen p=new Pen(Color.FromArgb(195,113,222,247),2))g.DrawEllipse(p,e.X-w*.48f,e.Y-h*.47f+bob,w*.96f,h*.94f);
        }
        private void DrawBolt(Graphics g,Bolt b){Color c=TypeColor(b.Type,b.Source.Level);float r=b.Type=="dwarf"?8:6;using(SolidBrush glow=new SolidBrush(Color.FromArgb(72,c)))g.FillEllipse(glow,b.X-r*2,b.Y-r*2,r*4,r*4);using(SolidBrush core=new SolidBrush(c))g.FillEllipse(core,b.X-r/2,b.Y-r/2,r,r);using(Pen tail=new Pen(Color.FromArgb(100,c),2))g.DrawLine(tail,b.X,b.Y,b.X+(b.X-b.Target.X)*.04f,b.Y+(b.Y-b.Target.Y)*.04f);}
        private void DrawBurst(Graphics g,Burst b){float q=b.Life/b.Duration,r=6+q*26;using(Pen p=new Pen(Color.FromArgb((int)(190*(1-q)),b.Color),2.5f))g.DrawEllipse(p,b.X-r,b.Y-r,r*2,r*2);using(SolidBrush s=new SolidBrush(Color.FromArgb((int)(150*(1-q)),b.Color)))for(int i=0;i<5;i++){float a=i*1.256f+clock*3;g.FillEllipse(s,b.X+(float)Math.Cos(a)*r-2,b.Y+(float)Math.Sin(a)*r-2,4,4);}}
        private void DrawPreview(Graphics g,float x,float y){bool valid=ValidSpot(x,y);Color c=valid?Color.FromArgb(90,123,223,116):Color.FromArgb(90,231,97,81);using(SolidBrush b=new SolidBrush(c))g.FillEllipse(b,x-22,y-8,44,16);using(Pen p=new Pen(valid?Color.FromArgb(225,140,235,121):Color.FromArgb(230,244,111,94),2)){g.DrawEllipse(p,x-29,y-15,58,30);if(!valid)g.DrawLine(p,x-18,y-18,x+18,y+18);}if(selectedType!=null&&heroes[selectedType.Sprite]!=null)g.DrawImage(heroes[selectedType.Sprite],new RectangleF(x-24,y-68,48,67));}
    }

    internal sealed class MciAudio : IDisposable
    {
        [DllImport("winmm.dll",CharSet=CharSet.Auto)] private static extern int mciSendString(string command,StringBuilder result,int length,IntPtr callback);
        private readonly string musicAlias="cady_music";
        private readonly Dictionary<string,string[]> pools=new Dictionary<string,string[]>();
        private readonly Dictionary<string,int> indices=new Dictionary<string,int>();
        private bool musicOpen;
        private int musicLevel=35,effectLevel=450;
        private static int EffectVolume(int value){double x=Math.Max(0,Math.Min(1000,value))/1000.0;return (int)Math.Round(Math.Pow(x,3.0)*1000.0);}
        private static int Send(string command){return mciSendString(command,null,0,IntPtr.Zero);}
        public MciAudio(string root)
        {
            string music=Path.Combine(root,"Assets","Music","Everlasting-Shine.mp3");if(File.Exists(music)){musicOpen=Send("open \""+music+"\" type mpegvideo alias "+musicAlias)==0;SetMusicVolume(musicLevel);}
            OpenPool(root,"gondor","asta-slash");OpenPool(root,"elf","yuno-wind");OpenPool(root,"dwarf","magna-fire");OpenPool(root,"aura","vanessa-thread");OpenPool(root,"ice","noelle-ice");OpenPool(root,"death","mordor-grunt");
        }
        private void OpenPool(string root,string key,string file){string p=Path.Combine(root,"Assets","Sfx",file+".wav");if(!File.Exists(p))return;string[] names=new string[3];int found=0;for(int i=0;i<3;i++){string alias="cady_"+key+"_"+i;if(Send("open \""+p+"\" type waveaudio alias "+alias)==0){names[found++]=alias;Send("setaudio "+alias+" volume to "+EffectVolume(effectLevel));}}if(found>0){Array.Resize(ref names,found);pools[key]=names;indices[key]=0;}}
        public void PlayMusic(int volume){if(!musicOpen)return;SetMusicVolume(volume);Send("play "+musicAlias+" repeat");}
        public void StopMusic(){if(musicOpen)Send("stop "+musicAlias);}
        public void SetMusicVolume(int value){musicLevel=value;if(musicOpen)Send("setaudio "+musicAlias+" volume to "+(value*10));}
        public void SetEffectVolume(int value){effectLevel=value;int actual=EffectVolume(value);foreach(string[] group in pools.Values)foreach(string alias in group)Send("setaudio "+alias+" volume to "+actual);}
        public void PlayEffect(string key){Play(key);}
        public void PlayDeath(){Play("death");}
        private void Play(string key){if(effectLevel<=0||!pools.ContainsKey(key))return;string[] group=pools[key];int i=indices[key]++%group.Length;Send("play "+group[i]+" from 0");}
        public void Dispose(){StopMusic();if(musicOpen)Send("close "+musicAlias);foreach(string[] group in pools.Values)foreach(string alias in group){Send("stop "+alias);Send("close "+alias);}}
    }
}
