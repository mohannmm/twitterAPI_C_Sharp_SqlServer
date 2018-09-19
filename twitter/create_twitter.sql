USE master
GO

/****** Object:  Database Twitter_db     ******/
IF DB_ID('Twitter') IS NOT NULL
	DROP DATABASE Twitter
GO

CREATE DATABASE Twitter
GO 

USE Twitter
GO

/****** Object:  Table Users  ******/   
CREATE TABLE tblUsers(
	UserID int PRIMARY KEY IDENTITY(1,1) NOT NULL,
	UserName varchar(50) NOT NULL,
	UserHandle varchar(50) NOT NULL,
	UserTweetCount int DEFAULT (0) NOT NULL,
	UserPoliticalEngagement  float DEFAULT(0) NOT NULL,
	UserBias float DEFAULT(0.5) NOT NULL
)
GO


/****** Object:  Table tblKeyUsers ******/   
CREATE TABLE tblKeyUsers(
	KeyUserID int PRIMARY KEY IDENTITY(1,1) NOT NULL,
	--KeyUserName varchar(50) NOT NULL,
	KeyUserHandle varchar(50) NOT NULL,
	KeyUserBias float DEFAULT(0.5) NOT NULL
)
GO

/****** Object:  Table tblFollowing  ******/   
CREATE TABLE tblFollowing(
	UserID int FOREIGN KEY REFERENCES tblUsers(UserID) NOT NULL,
	FollowingID int PRIMARY KEY IDENTITY(1,1) NOT NULL,
	FollowingHandle varchar(50) NOT NULL,
)
GO


/****** Object:  Table tblTweets ******/
CREATE TABLE tblTweets (
	TweetID	int		PRIMARY KEY IDENTITY	NOT NULL,
	UserID		int		FOREIGN KEY REFERENCES tblUsers(UserID),
	TweetString	varchar(240)	DEFAULT('')			NOT NULL,
	LikeCount		int		DEFAULT(0)				NOT NULL,
	RetweetCount		int		DEFAULT(0)				NOT NULL
)
GO



/****** Object:  Table tblKeyWords ******/
CREATE TABLE tblKeyWords (
	KeyWordID	int		DEFAULT('')	NOT NULL,
	KeyWord		varchar(50)	DEFAULT('')	NOT NULL
)
GO

CREATE VIEW vwPoliticalTweets AS (
	SELECT *
	FROM tblTweets t JOIN tblKeyWords kw
	ON t.TweetString LIKE concat('%' , kw.KeyWord , '%')
)
GO

CREATE VIEW vwPoliticalFollowings AS (
	SELECT f.UserID, u.UserHandle, ku.KeyUserHandle, ku.KeyUserBias
	FROM tblFollowing f JOIN tblKeyUsers ku ON
		f.FollowingHandle LIKE concat('%', ku.KeyUserHandle, '%')
		JOIN tblUsers u ON f.UserID = u.UserID -- test this
)
GO




-------- Stored Procedures ------------

-- A procedure that uses vwPoliticalFollowings to calculate the political bias of a user from 0-1.
-- A bias of close to 0 represents liberal views, 1 represents conservative views, close to 0.5 represents moderate views
-- Returns the bias value and assigns updates UserBias in tblUsers. Returns -1 if the user does not exist.
CREATE PROCEDURE [dbo].[spCalculateBias] 
	@UserID	int -- can be UserID or UserHandle depending on the implementation
AS
	DECLARE @v_result float = -1
	DECLARE @v_count int

	IF EXISTS ( 
				SELECT NULL
				FROM tblUsers
				WHERE UserID = @UserID
			)	BEGIN 


			SELECT  @v_count = COUNT(KeyUserBias)
			FROM vwPoliticalFollowings
			WHERE UserID = @UserID

			IF (@v_count > 0) BEGIN

				SELECT @v_result = AVG(CAST(KeyUserBias AS float))
				FROM vwPoliticalFollowings
				WHERE UserID = @UserID

				END

			UPDATE tblUsers
			SET UserBias = @v_result
			WHERE UserID = @UserID
			
			END

			SELECT * FROM tblUsers WHERE UserID = @UserID

			RETURN 
GO


-- A procedure that uses vwPoliticalTweets to calculate the level of a user's political engagement 
-- as a percentage expressed as a float (decimal value). 
-- Returns the level of political engagement and updates PoliticalEngagement in tblUsers 
CREATE PROCEDURE [dbo].[spCalculatePoliticalEngagement]
	@UserID int
AS
	DECLARE @v_result float = -1

	IF EXISTS ( 
			SELECT NULL
			FROM tblUsers
			WHERE UserID = @UserID AND UserTweetCount != 0
		)	BEGIN 

	

		SELECT @v_result =  CAST(COUNT(DISTINCT pt.TweetID) AS float) / CAST(u.UserTweetCount AS float) -- where does 'DISTINCT' go?
		FROM vwPoliticalTweets pt JOIN tblUsers u
			ON pt.UserID = u.UserID
		GROUP BY pt.UserID, u.UserTweetCount

		UPDATE tblUsers
		SET UserPoliticalEngagement = @v_result
		WHERE UserID = @UserID

		END

		SELECT * FROM tblUsers WHERE UserID = @UserID

		RETURN
GO


-- This version calculates without needing UserTweetCount from tblUsers
CREATE PROCEDURE [dbo].[spCalculatePoliticalEngagementV2]
	@UserID int
AS
	DECLARE @v_result float = -1
	DECLARE @v_tweetCount float

	IF EXISTS ( 
			SELECT NULL
			FROM tblUsers
			WHERE UserID = @UserID
		)	BEGIN 

		SELECT @v_tweetCount = CAST(COUNT(DISTINCT TweetID) AS float)
		FROM tblTweets
		WHERE UserID = @UserID

		SELECT @v_result =  CAST(COUNT(DISTINCT pt.TweetID) AS float) / @v_tweetCount -- where does 'DISTINCT' go?
		FROM vwPoliticalTweets pt JOIN tblUsers u
			ON pt.UserID = u.UserID
		GROUP BY pt.UserID, u.UserTweetCount

		UPDATE tblUsers
		SET UserPoliticalEngagement = @v_result
		WHERE UserID = @UserID

		END

		SELECT * FROM tblUsers WHERE UserID = @UserID

		RETURN
GO




CREATE PROCEDURE [dbo].[spAddUser]
	@UserName varchar(40),
	@UserHandle varchar(40),
	@UserTweetCount int
	
AS
	IF NOT EXISTS (SELECT NULL
						FROM tblUsers
						WHERE UserName = @UserName AND
								UserHandle = @UserHandle AND
								UserTweetCount = @UserTweetCount
						) BEGIN
						INSERT INTO tblUsers(UserName, UserHandle, UserTweetCount)
						VALUES (@UserName, @UserHandle, @UserTweetCount)
						SELECT @@IDENTITY AS newID
						RETURN
	END
GO

-- Adds a single tweet to tblTweets
CREATE PROCEDURE [dbo].[spAddTweet]
	@UserID int,
	@TweetString varchar(240),
	@LikeCount int,
	@RetweetCount int
AS
	IF EXISTS(SELECT NULL 
					FROM tblUsers
					WHERE UserID = @UserID
					) BEGIN

	IF NOT EXISTS ( SELECT NULL
					FROM tblTweets
					WHERE	UserID = @UserID AND 
							TweetString = @TweetString
					) BEGIN
					INSERT INTO tblTweets (UserID, TweetString, LikeCount, RetweetCount)
					VALUES (@UserID, @TweetString, @LikeCount, @RetweetCount)
					SELECT @@IDENTITY AS newID
					RETURN
	END
	END
GO



-- Adds an account to tblFollowing that a user from tblUsers follows
CREATE PROCEDURE [dbo].[spAddFollowing]
	@UserID int,
	@FollowingHandle varchar(50)
AS
	IF NOT EXISTS ( SELECT NULL
					FROM tblFollowing
					WHERE @UserID = UserID AND
						@FollowingHandle = FollowingHandle
				  ) BEGIN
				  INSERT INTO tblFollowing (UserID, FollowingHandle)
				  VALUES (@UserID, @FollowingHandle)
				  SELECT @@IDENTITY AS newID
				RETURN
	END
GO


-- Returns the UserID of a specified UserHandle from tblUsers
CREATE PROCEDURE [dbo].[spGetUserID]
	@UserHandle VARCHAR(50)
AS
	SELECT *
	FROM tblUsers
	WHERE UserHandle = @UserHandle

RETURN 
GO


CREATE PROCEDURE [dbo].[spGetTop50Tweets]
	@UserID int
	AS

	SELECT DISTINCT TOP 50 * 
	FROM vwPoliticalTweets
	WHERE @UserID = UserID

RETURN 0
GO

CREATE PROCEDURE [dbo].[spGetTop5Followings]
	@UserID int
	AS

	SELECT TOP 5 * 
	FROM vwPoliticalFollowings
	WHERE @UserID = UserID

RETURN 0
GO
/*------ INSERTING FOR TESTING ------*/


INSERT tblUsers(UserName, UserHandle, UserTweetCount, UserPoliticalEngagement, UserBias) VALUES 
('Emmi Mackerel', 'emackerel0', 17, 0.1, 0.1),
('Aida Messier', 'amessier1', 31, 0.1, 0.3),
('Marianna Beau', 'mbeau2', 23, 0.4, 0.3),
('Carolan Cowherd', 'ccowherd3', 97, 0.5, 0.8),
('Pooh McKeady', 'pmckeady4', 78, 0.3, 0.4),
('Isahella Barenski', 'ibarenski5', 46, 0.0, 0.9),
('Lindsay Camelia', 'lcamelia6', 67, 0.6, 0.1),
('Faye Gierth', 'fgierth7', 100, 0.2, 0.0),
('Joline Airton', 'jairton8', 92, 0.5, 0.5),
('Correna Treleven', 'ctreleven9', 31, 0.7, 0.9),
('Marylou Sant', 'msanta', 29, 0.9, 0.4),
('Lisette Oosthout de Vree', 'loosthoutb', 45, 0.3, 0.9),
('Amelita Camilli', 'acamillic', 60, 0.6, 0.0),
('Daniella Briscow', 'dbriscowd', 44, 0.3, 0.6),
('Joete Gregol', 'jgregole', 62, 0.9, 0.1),
('Ricoriki Pynn', 'rpynnf', 85, 0.1, 0.2),
('Ulberto Mussotti', 'umussottig', 38, 0.1, 0.4),
('Stinky Warters', 'swartersh', 5, 0.5, 0.2),
('Torr Dovey', 'tdoveyi', 24, 0.3, 0.0),
('Dimitry Drieu', 'ddrieuj', 10, 1.0, 0.7)
GO

INSERT tblFollowing(UserID, FollowingHandle) VALUES
(1, 'michellemalkin'),
(1, 'senatedems'),
(2, 'michaeljohns'),
(1, 'thisShouldNotAppearIn vwPoliticalFollowings')
GO

INSERT tblTweets(UserID, TweetString, LikeCount, RetweetCount) VALUES
(1, 'I like dogs', 5, 5),
(1, 'Weed should be legal', 5, 5),
(1, 'I like absenteeism', 5, 5)
GO



INSERT tblKeyUsers (KeyUserHandle, KeyUserBias) VALUES 
('michellemalkin',1),
('michaeljohns',1),
('johnboehner',1),
('sarahpalinusa',1),
('heritage',1),
('redstate',1),
('glennbeck',1),
('karlrove',1),
('newtgingrich',1),
('fredthompson',1),
('mittromney',1),
('ingrahmangle',1),
('joenbc',1),
('seanhannity',1),
('themrc',1),
('rnc',1),
('dickmorristweet',1),
('loyaltoliberty',1),
('hotairblog',1),
('usconservatives',1),
('christichat',1),
('gop',1),
('appsame',1),
('chucknellis',1),
('drmartyfox',1),
('carminezozzora',1),
('eroato',1),
('carlyfiorina',1),
('emfingersscout',1),
('a_m_perez',1),
('lrihendry',1),
('marylene58',1),
('reince',1),
('HouseGOP',1),
('meghanmccain',1),
('jstines3',1),
('danieljhannan',1),
('therickwilson',1),
('realdonaldtrump',1),
('donnabrazile',0),
('nancypelosi',0),
('thedemocrats',0),
('joebiden',0),
('senatedems',0),
('housedemocrats',0),
('people4bernie',0),
('dwstweets',0),
('politics_pr',0),
('docrocktex26',0),
('theclobra',0),
('skookerg',0),
('madeleine',0),
('mcspocky',0),
('kharyp',0),
('npquarterly',0),
('emilyslist',0),
('arkansasonline',0),
('co_rapunzel4',0),
('billmaher',0),
('buzzfeedben',0),
('jonlovett',0),
('chrismurphyct',0),
('heerjeet',0),
('deray',0),
('chrislhayes',0),
('ezraklein',0),
('jbouie',0),
('cjane87',0),
('noahpinion',0),
('yashar',0),
('mudede',0),
('kariyssdal',0),
('julietlapidos',0),
('chrislynnhedges',0),
('meaganmday',0),
('emmaogreen',0),
('obsoletedogma',0),
('johnathanlkrohn',0),
('cenkuygur',0),
('barackobama',0)
GO


INSERT tblKeyWords(KeyWordID, KeyWord) VALUES 
(1,'Absentee' ),
(2,'Accountable' ),
(3,'Activist' ),
(4,'Adverse' ),
(5,'Advertising' ),
(6,'Advice' ),
(7,'Advise' ),
(8,'Affiliation' ),
(9,'Aggressive' ),
(10,'Amendment' ),
(11,'Announcement' ),
(12,'Anthem' ),
(13,'Appeal' ),
(14,'Appearance' ),
(15,'Appoint' ),
(16,'Approach' ),
(17,'Appropriation' ),
(18,'Arguments' ),
(19,'Articulate' ),
(20,'Aspiration' ),
(21,'Asset' ),
(22,'Assimilation' ),
(23,'Atlarge' ),
(24,'Audience' ),
(25,'Authorization' ),
(26,'Background' ),
(27,'Bait' ),
(28,'Balanced budget' ),
(29,'Ballot' ),
(30,'Ballotbox' ),
(31,'Bandwagon' ),
(32,'Barnstorm' ),
(33,'Behavior' ),
(34,'Beliefs' ),
(35,'Biannual' ),
(36,'Bias' ),
(37,'Bicameral' ),
(38,'Bill' ),
(39,'Bipartisan' ),
(40,'Boondoggle' ),
(41,'Brochure' ),
(42,'Budget' ),
(43,'Bunk' ),
(44,'Bureaucracy' ),
(45,'Cabinet' ),
(46,'Campaign' ),
(47,'Candidate' ),
(48,'Canvass' ),
(49,'Capitalize' ),
(50,'Career' ),
(51,'Catalyst' ),
(52,'Caucus' ),
(53,'Ceiling' ),
(54,'Centrist' ),
(55,'Challenge' ),
(56,'Challenger' ),
(57,'Changes' ),
(58,'Charismatic' ),
(59,'Checks and balances' ),
(60,'Choice' ),
(61,'Citation' ),
(62,'Civic' ),
(63,'Coalition' ),
(64,'Coast-to-coast' ),
(65,'Coattail' ),
(66,'Collaboration' ),
(67,'Colleague' ),
(68,'Collective' ),
(69,'Commitments' ),
(70,'Committee' ),
(71,'Commonality' ),
(72,'Communication' ),
(73,'Compassion' ),
(74,'Concede' ),
(75,'Concessions' ),
(76,'Confidence' ),
(77,'Congress' ),
(78,'Congressional' ),
(79,'Conscience' ),
(80,'Consequence' ),
(81,'Conservative' ),
(82,'Constituent' ),
(83,'Constitution' ),
(84,'Consultation' ),
(85,'Contribution' ),
(86,'Controversy' ),
(87,'Convene' ),
(88,'Convention' ),
(89,'Council' ),
(90,'Curiosity' ),
(91,'Cycle' ),
(92,'Darkhorse' ),
(93,'Debate' ),
(94,'Decision' ),
(95,'Decisive' ),
(96,'Declaration' ),
(97,'Defeat' ),
(98,'Deficit' ),
(99,'Delegate' ),
(100,'Deliberate' ),
(101,'Deliberation' ),
(102,'Democracy' ),
(103,'Democrat' ),
(104,'Democratic' ),
(105,'Derision' ),
(106,'Destiny' ),
(107,'Diligent' ),
(108,'Diplomat' ),
(109,'Disapproval' ),
(110,'Discourse' ),
(111,'Discreet' ),
(112,'Discussion' ),
(113,'Disheartened' ),
(114,'Dishonesty' ),
(115,'Dissatisfaction' ),
(116,'District' ),
(117,'Distrust' ),
(118,'Diverse' ),
(119,'Division' ),
(120,'Dogma' ),
(121,'Dominate' ),
(122,'Donation' ),
(123,'Donor' ),
(124,'Dossier' ),
(125,'Dynamic' ),
(126,'Effective' ),
(127,'Efficient' ),
(128,'Elation' ),
(129,'Electoral college' ),
(130,'Elevate' ),
(131,'Eloquence' ),
(132,'Emphasis' ),
(133,'Enact' ),
(134,'Endorsement' ),
(135,'Engaging' ),
(136,'Equal' ),
(137,'Ethics' ),
(138,'Euphoria' ),
(139,'Excessive' ),
(140,'Executive' ),
(141,'Exitpoll' ),
(142,'Experience' ),
(143,'Faction' ),
(144,'Federal' ),
(145,'Feud' ),
(146,'Filibuster' ),
(147,'Flawed' ),
(148,'Focus' ),
(149,'Forum' ),
(150,'Fraud' ),
(151,'Freedom' ),
(152,'Frontrunner' ),
(153,'Fundamental' ),
(154,'Funding' ),
(155,'Fundraiser' ),
(156,'Gambit' ),
(157,'Gerrymander' ),
(158,'Glaring' ),
(159,'GOP' ),
(160,'Government' ),
(161,'Grassroots' ),
(162,'Grateful' ),
(163,'Handshakes' ),
(164,'Hardmoney' ),
(165,'HatchAct' ),
(166,'Heckle' ),
(167,'Historic' ),
(168,'Honesty' ),
(169,'Hooray' ),
(170,'Hypocrisy' ),
(171,'Immigrants' ),
(172,'Impound' ),
(173,'Inalienable' ),
(174,'Incentive' ),
(175,'Incorporate' ),
(176,'Incumbency' ),
(177,'Incumbent' ),
(178,'Independent' ),
(179,'Indulge' ),
(180,'Infallible' ),
(181,'Influx' ),
(182,'Informative' ),
(183,'Initiative' ),
(184,'Innuendo' ),
(185,'Inspiring' ),
(186,'Integrity' ),
(187,'Interests' ),
(188,'Investigate' ),
(189,'Involvement' ),
(190,'Irresponsible' ),
(191,'Issues' ),
(192,'Jeopardy' ),
(193,'JUBILANT' ),
(194,'Judge' ),
(195,'Judicial' ),
(196,'Keen' ),
(197,'Knowledge' ),
(198,'Lameduck' ),
(199,'Landslide' ),
(200,'Law' ),
(201,'Leader' ),
(202,'Leadership' ),
(203,'Leanings' ),
(204,'Legal' ),
(205,'Legalization' ),
(206,'Legislature' ),
(207,'Liberal' ),
(208,'Listening' ),
(209,'Lobbyist' ),
(210,'Lone' ),
(211,'Loser' ),
(212,'Loss' ),
(213,'Loyalty' ),
(214,'Magistrate' ),
(215,'Majority' ),
(216,'Mandate' ),
(217,'Meaningful' ),
(218,'Measures' ),
(219,'Media' ),
(220,'Meetings' ),
(221,'Mentor' ),
(222,'Mid term election' ),
(223,'Minority' ),
(224,'Misinformation' ),
(225,'Motives' ),
(226,'Mudslinging' ),
(227,'National' ),
(228,'Nationwide' ),
(229,'Negativity' ),
(230,'Network' ),
(231,'Nominate' ),
(232,'Nominee' ),
(233,'Nonpartisan' ),
(234,'Obligation' ),
(235,'Obsequious' ),
(236,'Offensive' ),
(237,'Office' ),
(238,'Official' ),
(239,'Oldboy' ),
(240,'Opine' ),
(241,'Opinion' ),
(242,'Opinionated' ),
(243,'Opportunity' ),
(244,'Opposition' ),
(245,'Orator' ),
(246,'Outspoken' ),
(247,'Ovation' ),
(248,'PAC(politicalactioncommittee)' ),
(249,'Pamphlets' ),
(250,'Pardon' ),
(251,'Participation' ),
(252,'Partisanship' ),
(253,'Party' ),
(254,'Patriotism' ),
(255,'Petition' ),
(256,'Platform' ),
(257,'Pledge' ),
(258,'Plurality' ),
(259,'Polarize' ),
(260,'Policy' ),
(261,'Polite' ),
(262,'Politician' ),
(263,'Politics' ),
(264,'Poll' ),
(265,'Polling Place' ),
(266,'Pollster' ),
(267,'Popular' ),
(268,'Popularity' ),
(269,'Porkbarrel' ),
(270,'Positionpaper' ),
(271,'Pragmatist' ),
(272,'Praise' ),
(273,'Precinct' ),
(274,'Predictions' ),
(275,'Prescient' ),
(276,'Press' ),
(277,'Pride' ),
(278,'Primary' ),
(279,'Priority' ),
(280,'Proactive' ),
(281,'Process' ),
(282,'Progressive' ),
(283,'Projection' ),
(284,'Promises' ),
(285,'Propaganda' ),
(286,'Proponent' ),
(287,'Proposal' ),
(288,'Purpose' ),
(289,'Query' ),
(290,'Quest' ),
(291,'Questions' ),
(292,'Quorum' ),
(293,'Quotes' ),
(294,'Race' ),
(295,'Ratify' ),
(296,'Re-election' ),
(297,'Reapportionment' ),
(298,'Recall' ),
(299,'Recognition' ),
(300,'Reconciliation' ),
(301,'Recount' ),
(302,'Recrimination' ),
(303,'Redistrict' ),
(304,'Referendum' ),
(305,'Reform' ),
(306,'Registration' ),
(307,'Regulate' ),
(308,'Representation' ),
(309,'Republican' ),
(310,'Rescind' ),
(311,'Resignation' ),
(312,'Resilience' ),
(313,'Restrictions' ),
(314,'Retort' ),
(315,'Reveal' ),
(316,'Revelations' ),
(317,'Revenues' ),
(318,'Rhetoric' ),
(319,'Rollcall' ),
(320,'Runoff' ),
(321,'Scope' ),
(322,'Senate' ),
(323,'Seniority' ),
(324,'Shift' ),
(325,'Shortcoming' ),
(326,'Shuffle' ),
(327,'Sidelines' ),
(328,'Sinecure' ),
(329,'Skill' ),
(330,'Slate' ),
(331,'Slogan' ),
(332,'Solicitation' ),
(333,'Solution' ),
(334,'Spar' ),
(335,'Spectacle' ),
(336,'Speculate' ),
(337,'Spending' ),
(338,'Spin' ),
(339,'Stakes' ),
(340,'Stance' ),
(341,'State''s rights' ),
(342,'Statute' ),
(343,'Strategist' ),
(344,'Strategy' ),
(345,'Strawpoll' ),
(346,'Stump' ),
(347,'Subcommittee' ),
(348,'Subjects' ),
(349,'Success' ),
(350,'Suffrage' ),
(351,'Support' ),
(352,'System' ),
(353,'Tactics' ),
(354,'Tally' ),
(355,'Taxpayer' ),
(356,'Term' ),
(357,'Termlimit' ),
(358,'Ticket' ),
(359,'Topic' ),
(360,'Trust' ),
(361,'Turnout' ),
(362,'Ultimate' ),
(363,'Unanimous' ),
(364,'Uncommitted' ),
(365,'Unfair' ),
(366,'Uniformity' ),
(367,'Unity' ),
(368,'Unknown' ),
(369,'Unopposed' ),
(370,'Unprecedented' ),
(371,'Unwind' ),
(372,'Upcoming' ),
(373,'Upset' ),
(374,'Vacancy' ),
(375,'Veto' ),
(376,'Viable' ),
(377,'Victor' ),
(378,'Victory' ),
(379,'Vie' ),
(380,'Viewpoint' ),
(381,'Views' ),
(382,'Violations' ),
(383,'VIP' ),
(384,'Volunteers' ),
(385,'Voter' ),
(386,'Vulnerability' ),
(387,'Ward' ),
(388,'Whistle-stop' ),
(389,'Wild-card' ),
(390,'Win' ),
(391,'Winner' ),
(392,'Withdraw' ),
(393,'Withhold' ),
(394,'Woo' ),
(395,'Xenophobic' ),
(396,'Yell' ),
(397,'Yield' ),
(398,'Zeal' ),
(399,'Zealous' ),
(400,'Zone' ),
(401,'Abortion' ),
(402,'Abstinence Sex Education' ),
(403,'Sex Education' ),
(404,'Acceptance' ),
(405,'Affirmative Action' ),
(406,'Affordable Care Act' ),
(407,'Agreement' ),
(408,'Ally' ),
(409,'American' ),
(410,'American Dream ' ),
(411,'American Exceptionalism' ),
(412,'American-Israeli Relationship' ),
(413,'Anti-Gay' ),
(414,'Anti-Science' ),
(415,'Arab Spring' ),
(416,'Atheism' ),
(417,'Atheist' ),
(418,'Authoritarian' ),
(419,'Authority' ),
(420,'Bailout' ),
(421,'Ballot Integrity' ),
(422,'Belief' ),
(423,'Believers' ),
(424,'Biased' ),
(425,'Biblical' ),
(426,'Big Agriculture' ),
(427,'Big Business' ),
(428,'Big Food' ),
(429,'Big Government' ),
(430,'Big Health' ),
(431,'Big Media' ),
(432,'Big Pharma' ),
(433,'Bigot' ),
(434,'Biological' ),
(435,'Birth Control' ),
(436,'Black Lives Matter' ),
(437,'BLM' ),
(438,'Bureau of Land Management' ),
(439,'Department of Interior' ),
(440,'Brave Space' ),
(441,'Capital Punishment' ),
(442,'Death Penalty' ),
(443,'Capitalism' ),
(444,'Carbon Footprint' ),
(445,'Certainty' ),
(446,'Change' ),
(447,'Character' ),
(448,'Charter Schools' ),
(449,'Chastity' ),
(450,'Christopher Columbus' ),
(451,'Civil Rights' ),
(452,'Civil Society' ),
(453,'Civility' ),
(454,'Class Warfare' ),
(455,'Class' ),
(456,'Classism' ),
(457,'Climate Change' ),
(458,'Climate Skeptic ' ),
(459,'Climate Change Denier' ),
(460,'Color Blindness' ),
(461,'Coming Out' ),
(462,'Common Core' ),
(463,'Common Ground' ),
(464,'Communism' ),
(465,'Communitarianism' ),
(466,'Community' ),
(467,'Complex' ),
(468,'Complicated' ),
(469,'Comprehensive Sex Education' ),
(470,'Compromise' ),
(471,'Condoms' ),
(472,'Confirmation Bias' ),
(473,'Conflict' ),
(474,'Conflict Improvement' ),
(475,'Conflict Resolution' ),
(476,'Consensus' ),
(477,'Conservation' ),
(478,'Constitutional' ),
(479,'Contestation' ),
(480,'Conversion Therapy' ),
(481,'Reparative Therapy' ),
(482,'Corporations' ),
(483,'Corruption' ),
(484,'Creationism' ),
(485,'Culture War' ),
(486,'National Debt' ),
(487,'Democratic/Democracy' ),
(488,'Development' ),
(489,'Dialogue' ),
(490,'Direct Democracy' ),
(491,'Disagreement' ),
(492,'Disagreement Practice' ),
(493,'Discrimination' ),
(494,'Diversity' ),
(495,'Drug Legalization' ),
(496,'Economy' ),
(497,'Electoral Reform' ),
(498,'Environmentalist' ),
(499,'Environmentalism' ),
(500,'Equal Rights' ),
(501,'Equality' ),
(502,'Equity' ),
(503,'Euthanasia' ),
(504,'Evolution' ),
(505,'Extreme' ),
(506,'Extremist' ),
(507,'Facts' ),
(508,'Fairness' ),
(509,'Faith' ),
(510,'Family' ),
(511,'Family Planning' ),
(512,'Family Values' ),
(513,'Far Left' ),
(514,'Far Right' ),
(515,'Fascism' ),
(516,'FDA ' ),
(517,'U.S. Food & Drug Administration' ),
(518,'Federal Government' ),
(519,'Federal Power' ),
(520,'Feminism' ),
(521,'Final Judgment' ),
(522,'Forced Treatment' ),
(523,'Fracking' ),
(524,'Freedom of Conscience' ),
(525,'Freedom of Religion ' ),
(526,'Religious Freedom ' ),
(527,'Religious Liberty' ),
(528,'Freedom of Speech' ),
(529,'Fundamentalism' ),
(530,'Gay Marriage' ),
(531,'Gender' ),
(532,'Gender Identity' ),
(533,'Gender Role' ),
(534,'Global Warming' ),
(535,'GMO' ),
(536,'Genetically Modified Organism' ),
(537,'Government Assistance' ),
(538,'Government Regulations' ),
(539,'Great Depression' ),
(540,'Great Society' ),
(541,'Gridlock' ),
(542,'Growth' ),
(543,'Gun Control' ),
(544,'Gun Rights' ),
(545,'Gun Violence' ),
(546,'Hard Work' ),
(547,'Hatred' ),
(548,'Health Freedom' ),
(549,'Heterosexism' ),
(550,'Home Schooling' ),
(551,'Homophobia' ),
(552,'Homosexuality' ),
(553,'Humanism' ),
(554,'Identity' ),
(555,'Illegals' ),
(556,'Illegal Immigrants' ),
(557,'Immigration' ),
(558,'Immigration Reform' ),
(559,'Individualism' ),
(560,'Inequality' ),
(561,'Inequity' ),
(562,'Integral Politics' ),
(563,'Intelligent Design' ),
(564,'International Law' ),
(565,'Invisible Hand' ),
(566,'Irrational' ),
(567,'Isolationism' ),
(568,'Israel' ),
(569,'Left-Wing' ),
(570,'LGBTQIA' ),
(571,'Liar' ),
(572,'Lying' ),
(573,'Liberal Media' ),
(574,'Libertarianism' ),
(575,'Libertarian Party' ),
(576,'Liberty' ),
(577,'Lifestyle Choice' ),
(578,'Marijuana' ),
(579,'Marriage' ),
(580,'Marriage Equality' ),
(581,'Marxist' ),
(582,'Marxism' ),
(583,'Media Elite' ),
(584,'Mental Health' ),
(585,'Microaggression' ),
(586,'Mixed-orientation Marriage' ),
(587,'Moderate' ),
(588,'Money in Politics' ),
(589,'Monoculture' ),
(590,'Monogamy' ),
(591,'Multiculturalism' ),
(592,'Narrow-Minded' ),
(593,'National Defense & National Security' ),
(594,'Neurodiversity' ),
(595,'Objective' ),
(596,'Objectivity' ),
(597,'Oppression' ),
(598,'Partisanship ' ),
(599,'Partisan' ),
(600,'Patriotic' ),
(601,'Patriot' ),
(602,'Peace' ),
(603,'Personal Responsibility' ),
(604,'Persuasion' ),
(605,'Planned Parenthood' ),
(606,'Polarization' ),
(607,'Politically Correct' ),
(608,'Pornography' ),
(609,'Power' ),
(610,'Prejudice' ),
(611,'Private Property' ),
(612,'Property Rights' ),
(613,'Privilege' ),
(614,'Proposition 8' ),
(615,'Pseudo-question' ),
(616,'Public Education' ),
(617,'Public Land' ),
(618,'Purity' ),
(619,'Queer' ),
(620,'Racial Inequity' ),
(621,'Racism ' ),
(622,'Racist' ),
(623,'Radical' ),
(624,'Rational' ),
(625,'Recovery' ),
(626,'Red/Blue Divide' ),
(627,'Redistribution of Wealth' ),
(628,'Refugee' ),
(629,'Religion' ),
(630,'Religious' ),
(631,'Responsibilities' ),
(632,'Right-Wing' ),
(633,'Rights' ),
(634,'Safe Spaces' ),
(635,'Same Sex Attraction ' ),
(636,'SSA' ),
(637,'School Choice' ),
(638,'Scientific' ),
(639,'Second Amendment Rights' ),
(640,'Second Coming' ),
(641,'Self-Reliance' ),
(642,'Separation of Church and State' ),
(643,'Service' ),
(644,'Sexual Orientation' ),
(645,'Sexuality' ),
(646,'Sin' ),
(647,'Single Payer' ),
(648,'Socialized Medicine' ),
(649,'Sitting with your Discomfort' ),
(650,'Social Justice' ),
(651,'Social Responsibility and Social Justice' ),
(652,'Socialism' ),
(653,'Spiritual Diversity' ),
(654,'State Capitalism' ),
(655,'Stem Cell Research' ),
(656,'Stereotypes' ),
(657,'Sustainability' ),
(658,'Sustainable' ),
(659,'Terrorism' ),
(660,'Traditional Family' ),
(661,'Transgender' ),
(662,'Transpartisan' ),
(663,'Treasonous Friendship' ),
(664,'Treatment Outcomes' ),
(665,'Trigger Warning' ),
(666,'Trolls' ),
(667,'Trustworthy Rival' ),
(668,'Truth' ),
(669,'Tyranny of Civility' ),
(670,'U.S.S.R.' ),
(671,'Unbiased' ),
(672,'United Nations' ),
(673,'United' ),
(674,'Virginity' ),
(675,'Virtue' ),
(676,'Voter Registration' ),
(677,'War on Christmas' ),
(678,'War on Terror' ),
(679,'Welfare State' ),
(680,'Welfare System' ),
(681,'White Privilege' ),
(682,'Wilderness' ),
(683,'Women’s Rights' ),
(684,'World Government' ),
(685,'World Peace' ),
(686,'Zionism' ),
(687, 'Pot'),
(688, 'Weed'),
(689, 'USSR'),
(690, 'Trade war'),
(691, 'Obama'),
(692, 'Trump'),
(693, 'Afghanistan'),
(694, 'Reagan'),
(695, 'Iran'),
(696, 'China'),
(697, 'Drugs'),
(698, 'Pharma'),
(699, 'War on drugs'),
(700, 'Sessions'),
(701, 'Jeff Sessions'),
(702, 'precedent'),
(703, 'court'),
(704, 'supreme court'),
(705, 'central bank'),
(706, 'nixon'),
(707, 'alien'),
(708, 'legal weed'),
(709, 'cannabis'),
(710, 'THC'),
(711, 'capitol hill'),
(712, 'capital hill'),
(713, 'the hill'),
(714, 'nazi'),
(715, 'anti-semite'),
(716, 'anti semite'),
(717, 'anti-semitism'),
(718, 'anti semitism')
GO
